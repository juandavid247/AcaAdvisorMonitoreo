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
$ComputerName = $env:COMPUTERNAME

function Get-MachineDeviceId {
    try {
        $mguid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -ErrorAction SilentlyContinue).MachineGuid
        if ($mguid) { return $mguid.Trim().ToLower() }
    } catch {}
    try {
        $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        if ($adapter -and $adapter.MacAddress) { return ($adapter.MacAddress -replace '-', ':').ToUpper() }
    } catch {}
    return ""
}

$DeviceId = Get-MachineDeviceId

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

# Habilitar DPI-Aware nativo para capturar pixeles reales sin borrosidad en escalas 125%/150%
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AcaDpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
    public static void Enable() {
        try {
            if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return;
        } catch {}
        try { SetProcessDPIAware(); } catch {}
    }
}
"@ -ErrorAction SilentlyContinue
    [AcaDpiHelper]::Enable()
} catch {}

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1

$QualityProfiles = @{
    sd  = @{ maxW = 640;  jpegQ = 50L; intervalMs = 2000 }
    hd  = @{ maxW = 1280; jpegQ = 82L; intervalMs = 400  }
    fhd = @{ maxW = 1920; jpegQ = 82L; intervalMs = 650  }
}

$EncParamsByQuality = @{}
foreach ($qk in $QualityProfiles.Keys) {
    $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$QualityProfiles[$qk].jpegQ)
    $EncParamsByQuality[$qk] = $ep
}

function Get-ScreenFrame([string]$quality = "sd") {
    try {
        if (-not $QualityProfiles.ContainsKey($quality)) { $quality = "sd" }
        $prof = $QualityProfiles[$quality]
        $maxW = [int]$prof.maxW
        $ep   = $EncParamsByQuality[$quality]

        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $bounds = $screen.Bounds
        if ($bounds.Width -le 0 -or $bounds.Height -le 0) { return $null }

        $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $gfx.Dispose()

        $targetW = $bounds.Width
        $targetH = $bounds.Height
        $finalBmp = $bmp

        if ($targetW -gt $maxW) {
            $ratio = ([double]$maxW) / [double]$targetW
            $targetW = $maxW
            $targetH = [int][math]::Round($targetH * $ratio)
            if (($targetH % 2) -ne 0) { $targetH += 1 }

            $resized = New-Object System.Drawing.Bitmap($targetW, $targetH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $rgfx = [System.Drawing.Graphics]::FromImage($resized)
            $rgfx.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $rgfx.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $rgfx.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $rgfx.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $rgfx.DrawImage($bmp, 0, 0, $targetW, $targetH)
            $rgfx.Dispose()
            $bmp.Dispose()
            $finalBmp = $resized
        }

        $ms = New-Object System.IO.MemoryStream
        $finalBmp.Save($ms, $jpegCodec, $ep)
        $finalBmp.Dispose()

        $b64 = [Convert]::ToBase64String($ms.ToArray())
        $ms.Dispose()

        return @{
            base64  = $b64
            width   = $targetW
            height  = $targetH
            aspect  = [math]::Round(([double]$targetW / [double]$targetH), 6)
            quality = $quality
        }
    } catch {
        Write-StreamLog "Error captura ($quality): $_"
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
                $loginHeaders = @{
                    "Client-Device" = $ComputerName
                    "X-Device-Id"   = $DeviceId
                }
                $loginBody = @{ email = $AgentEmail; password = $AgentPass; macId = $DeviceId } | ConvertTo-Json -Compress
                $loginRes = Invoke-RestMethod -Uri $LoginUrl -Method Post -Headers $loginHeaders -Body $loginBody -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
                if ($loginRes -and $loginRes.accessToken) {
                    $token = [string]$loginRes.accessToken
                    if ($auth.mode -eq "office") {
                        try {
                            $hkcuAuth = "HKCU:\Software\screen\empm\auth"
                            if (-not (Test-Path $hkcuAuth)) { New-Item -Path $hkcuAuth -Force | Out-Null }
                            Set-ItemProperty -Path $hkcuAuth -Name "token" -Value $token -Force
                        } catch {}
                    }
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

        $authMsg = @{
            type          = "agent_auth"
            token         = $token
            device_id     = $DeviceId
            computer_name = $ComputerName
        } | ConvertTo-Json -Compress
        Send-WsText $ws $authMsg
        Write-StreamLog "Conectado y autenticado en $WsUrl ($AgentEmail, PC=$ComputerName, Device=$DeviceId)"

        $recvBuf = New-Object byte[] 8192
        $recvSeg = New-Object System.ArraySegment[byte](,$recvBuf)
        $recvTask = $ws.ReceiveAsync($recvSeg, [System.Threading.CancellationToken]::None)

        $isStreaming = $false
        $streamQuality = "sd"
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
                        $prevQ = $streamQuality
                        $wasStreaming = $isStreaming
                        if ($msg -match 'quality:fhd') { $streamQuality = "fhd" }
                        elseif ($msg -match 'quality:hd') { $streamQuality = "hd" }
                        else { $streamQuality = "sd" }
                        $isStreaming = $true
                        if ((-not $wasStreaming) -or ($prevQ -ne $streamQuality)) {
                            $lastSent = (Get-Date).AddSeconds(-30)
                            Write-StreamLog "Streaming en vivo ACTIVADO (calidad=$streamQuality)."
                        }
                    } elseif ($msg -like '*stop sending images*') {
                        $isStreaming = $false
                        $streamQuality = "sd"
                        Write-StreamLog "Admin salio: streaming en vivo en espera (SD standby)."
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

            $activeIntervalMs = if ($isStreaming) { [int]$QualityProfiles[$streamQuality].intervalMs } else { 25000 }
            $elapsed = ((Get-Date) - $lastSent).TotalMilliseconds
            if ($elapsed -ge $activeIntervalMs) {
                $targetQ = if ($isStreaming) { $streamQuality } else { "sd" }
                $frame = Get-ScreenFrame -quality $targetQ
                if ($frame -and $frame.base64) {
                    $payload = @{
                        type          = "start_image_stream"
                        device_id     = $DeviceId
                        computer_name = $ComputerName
                        quality       = $frame.quality
                        image0        = $frame.base64
                        screenData0   = @{
                            aspectRatio0 = $frame.aspect
                            width0 = $frame.width
                            height0 = $frame.height
                        }
                    } | ConvertTo-Json -Depth 4 -Compress
                    Send-WsText $ws $payload
                    $lastSent = Get-Date
                }
            }

            Start-Sleep -Milliseconds 100
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
