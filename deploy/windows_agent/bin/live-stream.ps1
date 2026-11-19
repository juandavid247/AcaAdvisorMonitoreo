# ACA Advisor S.A.S. - Live Monitoring Screen Module (Stealth & Visible)
param()

$ErrorActionPreference = "SilentlyContinue"

# Evitar instancias duplicadas (Mutex global)
$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex($true, "Global\ACAAdvisorLiveStream", [ref]$mutexCreated)
if (-not $mutexCreated) { exit 0 }

$BaseDir    = $PSScriptRoot
$ConfigPath = Join-Path $BaseDir "configs\stream.json"
$LogDir     = Join-Path $BaseDir "logs"
if (-not (Test-Path $LogDir)) { try { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null } catch {} }
$LogFile    = if (Test-Path $LogDir) { Join-Path $LogDir "streamLog.txt" } else { Join-Path $env:TEMP "aca_streamLog.txt" }
$MaxLogBytes = 5MB

function Write-StreamLog($msg) {
    try {
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $MaxLogBytes)) {
            $oldLog = "$LogFile.old"
            if (Test-Path $oldLog) { Remove-Item $oldLog -Force -ErrorAction SilentlyContinue }
            Move-Item -Path $LogFile -Destination $oldLog -Force -ErrorAction SilentlyContinue
        }
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

function Get-AgentAuth {
    $server      = "192.168.0.155"
    $email       = ""
    $pass        = ""
    $token       = ""
    $mode        = "office"
    $useHttps    = $false
    $loginUrl    = ""
    $realtimeUrl = ""

    if (Test-Path $ConfigPath) {
        try {
            $cfg = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            if ($cfg.server)      { $server      = [string]$cfg.server }
            if ($cfg.email)       { $email       = [string]$cfg.email }
            if ($cfg.password)    { $pass        = [string]$cfg.password }
            if ($cfg.mode)        { $mode        = [string]$cfg.mode }
            if ($null -ne $cfg.useHttps) { $useHttps = [bool]$cfg.useHttps }
            if ($cfg.loginUrl)    { $loginUrl    = [string]$cfg.loginUrl }
            if ($cfg.realtimeUrl) { $realtimeUrl = [string]$cfg.realtimeUrl }
        } catch {}
    }

    # En modo visible (personal) o si el agente actualizo credenciales en QSettings, priorizar HKCU/HKLM
    $authPaths = @(
        "HKCU:\Software\screen\empm\auth",
        "HKLM:\Software\screen\empm\auth"
    )
    foreach ($ap in $authPaths) {
        try {
            if (Test-Path $ap) {
                $props = Get-ItemProperty -Path $ap -ErrorAction SilentlyContinue
                if ($props.email -and ($mode -eq "personal" -or -not $email)) {
                    $email = [string]$props.email
                }
                if ($props.crypto_password -and ($mode -eq "personal" -or -not $pass)) {
                    $pass = [string]$props.crypto_password
                }
                if ($props.token -and -not $token) {
                    $token = [string]$props.token
                }
            }
        } catch {}
    }

    if (-not $loginUrl) {
        $loginUrl = if ($useHttps) { "https://${server}/desktop/api/v3/employee/login" } else { "http://${server}:3004/api/v3/employee/login" }
    }
    if (-not $realtimeUrl) {
        $realtimeUrl = if ($useHttps) { "wss://${server}/ws/realtime" } else { "ws://${server}:3003" }
    }

    return @{
        server      = $server.Trim()
        email       = $email.Trim()
        password    = $pass.Trim()
        token       = $token.Trim()
        mode        = $mode
        loginUrl    = $loginUrl.Trim()
        realtimeUrl = $realtimeUrl.Trim()
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
$encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 55L)

function Get-ScreenFrame {
    try {
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $bounds = $screen.Bounds
        if ($bounds.Width -le 0 -or $bounds.Height -le 0) { return $null }

        $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $gfx.Dispose()

        $targetW = $bounds.Width
        $targetH = $bounds.Height
        if ($targetW -gt 1280) {
            $ratio = 1280.0 / [double]$targetW
            $targetW = 1280
            $targetH = [int][math]::Round($targetH * $ratio)
        }

        $resized = New-Object System.Drawing.Bitmap($targetW, $targetH)
        $rgfx = [System.Drawing.Graphics]::FromImage($resized)
        $rgfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $rgfx.DrawImage($bmp, 0, 0, $targetW, $targetH)
        $rgfx.Dispose()
        $bmp.Dispose()

        $ms = New-Object System.IO.MemoryStream
        $resized.Save($ms, $jpegCodec, $encParams)
        $resized.Dispose()

        $b64 = [Convert]::ToBase64String($ms.ToArray())
        $ms.Dispose()

        return @{
            base64 = $b64
            width  = $targetW
            height = $targetH
            aspect = [math]::Round(([double]$targetW / [double]$targetH), 6)
        }
    } catch {
        Write-StreamLog "Error captura: $_"
        return $null
    }
}

function Send-WsText($ws, $text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $seg = New-Object System.ArraySegment[byte](,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
}

Write-StreamLog "=== Iniciando ACA Advisor Live Screen Module ==="

while ($true) {
    $ws = $null
    try {
        $auth       = Get-AgentAuth
        $AgentEmail = $auth.email
        $AgentPass  = $auth.password
        $LoginUrl   = $auth.loginUrl
        $WsUrl      = $auth.realtimeUrl
        $token      = ""

        if (-not $AgentEmail -and -not $auth.token) {
            Write-StreamLog "Esperando credenciales de sesion del empleado (modo=$($auth.mode))..."
            Start-Sleep -Seconds 10
            continue
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if ($AgentEmail -and $AgentPass) {
            try {
                $loginBody = @{ email = $AgentEmail; password = $AgentPass } | ConvertTo-Json -Compress
                $loginRes = Invoke-RestMethod -Uri $LoginUrl -Method Post -Body $loginBody -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
                if ($loginRes -and $loginRes.accessToken) {
                    $token = $loginRes.accessToken
                }
            } catch {
                Write-StreamLog "Login fallido para ${AgentEmail}: $_"
            }
        }

        if (-not $token -and $auth.token) {
            $token = $auth.token
        }

        if (-not $token) {
            Write-StreamLog "Sin accessToken disponible ($AgentEmail). Reintentando en 10s..."
            Start-Sleep -Seconds 10
            continue
        }

        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $wsUri = New-Object System.Uri($WsUrl)
        $ws.ConnectAsync($wsUri, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

        $authMsg = @{ type = "agent_auth"; token = $token } | ConvertTo-Json -Compress
        Send-WsText $ws $authMsg
        Write-StreamLog "Conectado y autenticado en $WsUrl ($AgentEmail)"

        $recvBuf = New-Object byte[] 8192
        $recvSeg = New-Object System.ArraySegment[byte](,$recvBuf)
        $recvTask = $ws.ReceiveAsync($recvSeg, [System.Threading.CancellationToken]::None)

        $isStreaming = $false
        $lastSent = (Get-Date).AddSeconds(-30)
        $lastAuthCheck = Get-Date

        while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            if ($recvTask.IsCompleted) {
                $res = $recvTask.GetAwaiter().GetResult()
                if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    Write-StreamLog "Servidor cerro conexion WebSocket."
                    break
                }
                if ($res.Count -gt 0) {
                    $msg = [System.Text.Encoding]::UTF8.GetString($recvBuf, 0, $res.Count)
                    if ($msg -like '*Start sending image*') {
                        $isStreaming = $true
                        $lastSent = (Get-Date).AddSeconds(-30)
                        Write-StreamLog "Admin observando: streaming en vivo ACTIVADO."
                    } elseif ($msg -like '*stop sending images*') {
                        $isStreaming = $false
                        Write-StreamLog "Admin salio: streaming en vivo en espera."
                    }
                }
                $recvTask = $ws.ReceiveAsync($recvSeg, [System.Threading.CancellationToken]::None)
            }

            # Detectar cambio de usuario en modo visible (personal)
            if (((Get-Date) - $lastAuthCheck).TotalSeconds -ge 30) {
                $lastAuthCheck = Get-Date
                $curAuth = Get-AgentAuth
                if ($curAuth.email -and $curAuth.email -ne $AgentEmail) {
                    Write-StreamLog "Cambio de usuario detectado ($AgentEmail -> $($curAuth.email)). Reconectando..."
                    break
                }
            }

            $elapsed = ((Get-Date) - $lastSent).TotalMilliseconds
            if (($isStreaming -and $elapsed -ge 1500) -or ($elapsed -ge 25000)) {
                $frame = Get-ScreenFrame
                if ($frame -and $frame.base64) {
                    $payload = @{
                        type = "start_image_stream"
                        image0 = $frame.base64
                        screenData0 = @{
                            aspectRatio0 = $frame.aspect
                            width0 = $frame.width
                            height0 = $frame.height
                        }
                    } | ConvertTo-Json -Depth 4 -Compress
                    Send-WsText $ws $payload
                    $lastSent = Get-Date
                }
            }

            Start-Sleep -Milliseconds 250
        }
    } catch {
        Write-StreamLog "Error en bucle de streaming: $_"
    } finally {
        if ($ws) {
            try { $ws.Dispose() } catch {}
        }
    }
    Start-Sleep -Seconds 5
}
