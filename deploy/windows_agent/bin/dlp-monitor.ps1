# ==============================================================================
# ACA ADVISOR S.A.S. - Modulo DLP & Capturas Automaticas (USB, Clipboard, Print,
# Bloqueo Web/Apps y Screenshots Periodicos)
# Debe ejecutarse con: powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File dlp-monitor.ps1
# ==============================================================================
param()

$ErrorActionPreference = "SilentlyContinue"
$BaseDir     = $PSScriptRoot
$ConfigPath  = Join-Path $BaseDir "configs\stream.json"
$LogDir      = Join-Path $BaseDir "logs"
if (-not (Test-Path $LogDir)) { try { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null } catch {} }
$LogFile     = if (Test-Path $LogDir) { Join-Path $LogDir "dlpLog.txt" } else { Join-Path $env:TEMP "aca_dlpLog.txt" }
$MaxLogBytes = 5MB
$Computer    = $env:COMPUTERNAME

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

# Evitar instancias duplicadas
$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex($true, "Global\ACAAdvisorDLPMonitor", [ref]$mutexCreated)
if (-not $mutexCreated) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

# Habilitar DPI-Aware nativo para capturas guardadas 720p HD nitidas sin borrosidad por escala Windows
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
$encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 82L)
$script:lastSavedScreenHash = ""
$script:lastSavedScreenTime = (Get-Date).AddMinutes(-10)

function Write-DlpLog($msg) {
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
    $server   = "192.168.0.155"
    $email    = ""
    $pass     = ""
    $token    = ""
    $mode     = "office"
    $useHttps = $false
    $loginUrl = ""
    $apiUrl   = ""

    if (Test-Path $ConfigPath) {
        try {
            $cfg = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            if ($cfg.server)   { $server   = [string]$cfg.server }
            if ($cfg.email)    { $email    = [string]$cfg.email }
            if ($cfg.password) { $pass     = [string]$cfg.password }
            if ($cfg.mode)     { $mode     = [string]$cfg.mode }
            if ($null -ne $cfg.useHttps) { $useHttps = [bool]$cfg.useHttps }
            if ($cfg.loginUrl) { $loginUrl = [string]$cfg.loginUrl }
            if ($cfg.apiUrl)   { $apiUrl   = [string]$cfg.apiUrl }
        } catch {}
    }

    foreach ($ap in @("HKCU:\Software\screen\empm\auth", "HKLM:\Software\screen\empm\auth")) {
        try {
            if (Test-Path $ap) {
                $props = Get-ItemProperty -Path $ap -ErrorAction SilentlyContinue
                if ($props.email -and ($mode -eq "personal" -or -not $email)) { $email = [string]$props.email }
                if ($props.crypto_password -and ($mode -eq "personal" -or -not $pass)) { $pass = [string]$props.crypto_password }
                if ($props.token -and -not $token) { $token = [string]$props.token }
            }
        } catch {}
    }

    if (-not $loginUrl) {
        $loginUrl = if ($useHttps) { "https://${server}/desktop/api/v3/employee/login" } else { "http://${server}:3004/api/v3/employee/login" }
    }
    if (-not $apiUrl) {
        $apiUrl = if ($useHttps) { "https://${server}/logs/api/v1" } else { "http://${server}:3001/api/v1" }
    }

    return @{
        server   = $server.Trim()
        email    = $email.Trim()
        password = $pass.Trim()
        token    = $token.Trim()
        mode     = $mode
        loginUrl = $loginUrl.Trim()
        apiUrl   = $apiUrl.Trim()
    }
}

function Get-Sha256($str) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($str)
    $hash = $sha.ComputeHash($bytes)
    $sha.Dispose()
    return ([BitConverter]::ToString($hash) -replace '-', '')
}

function Send-DlpEvent($apiBaseUrl, $token, $type, $title, $description) {
    if (-not $token) { return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $payload = @{
            events = @(
                @{
                    dataId      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    title       = [string]$title
                    type        = [string]$type
                    description = [string]$description
                    computer    = [string]$Computer
                }
            )
        } | ConvertTo-Json -Depth 4 -Compress

        $headers = @{ Authorization = "Bearer $token" }
        Invoke-RestMethod -Uri "${apiBaseUrl}/desktop/add-system-log" -Method Post -Headers $headers -Body $payload -ContentType "application/json; charset=utf-8" -TimeoutSec 10 -ErrorAction Stop | Out-Null
        Write-DlpLog "DLP enviado [type=$type] $title"
    } catch {
        Write-DlpLog "Error enviando DLP [type=$type]: $_"
    }
}

function Upload-PeriodicScreenshot($apiBaseUrl, $token) {
    if (-not $token) { return }
    try {
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $bounds = $screen.Bounds
        if ($bounds.Width -le 0 -or $bounds.Height -le 0) { return }

        $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $gfx.Dispose()

        $targetW = $bounds.Width
        $targetH = $bounds.Height
        $finalBmp = $bmp

        if ($targetW -gt 1280) {
            $ratio = 1280.0 / [double]$targetW
            $targetW = 1280
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
        $finalBmp.Save($ms, $jpegCodec, $encParams)
        $finalBmp.Dispose()
        $jpgBytes = $ms.ToArray()
        $ms.Dispose()

        # Deduplicacion inteligente: omitir subida duplicada si pantalla no cambio en <5 min
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $frameHash = ([BitConverter]::ToString($sha.ComputeHash($jpgBytes)) -replace '-', '')
        $sha.Dispose()
        $nowTs = Get-Date
        if ($frameHash -eq $script:lastSavedScreenHash -and (($nowTs - $script:lastSavedScreenTime).TotalSeconds -lt 300)) {
            return
        }

        $utcNow = $nowTs.ToUniversalTime()
        $fileName = "screenshot_$($utcNow.ToString('yyyy-MM-dd_HH-mm-ss')).jpg"

        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds(15)
        $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $token)

        $form = New-Object System.Net.Http.MultipartFormDataContent
        $fileContent = New-Object System.Net.Http.ByteArrayContent(,$jpgBytes)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/jpeg")
        $form.Add($fileContent, "screenshots", $fileName)
        $form.Add((New-Object System.Net.Http.StringContent($utcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"))), "time")

        $resp = $client.PostAsync("${apiBaseUrl}/desktop/upload-screenshots", $form).GetAwaiter().GetResult()
        if ($resp.IsSuccessStatusCode) {
            $script:lastSavedScreenHash = $frameHash
            $script:lastSavedScreenTime = $nowTs
            Write-DlpLog "Screenshot 720p HD subido ($fileName, $([math]::Round($jpgBytes.Length / 1KB, 1)) KB)"
        }
        $form.Dispose()
        $client.Dispose()
    } catch {
        Write-DlpLog "Error subiendo screenshot: $_"
    }
}

function Set-UsbBlockState($block) {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR"
        if (Test-Path $regPath) {
            $desired = if ($block) { 4 } else { 3 }
            $current = (Get-ItemProperty -Path $regPath -Name "Start" -ErrorAction SilentlyContinue).Start
            if ($current -ne $desired) {
                Set-ItemProperty -Path $regPath -Name "Start" -Value $desired -Type DWord -Force
                Write-DlpLog "Politica USBSTOR actualizada: Start=$desired (block=$block)"
            }
        }
    } catch {}
}

function Apply-WebsiteBlockList($domains) {
    try {
        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
        if (-not (Test-Path $hostsPath)) { return }
        $lines = Get-Content -Path $hostsPath -ErrorAction SilentlyContinue
        $clean = @()
        $inBlock = $false
        foreach ($l in $lines) {
            if ($l -eq "# BEGIN ACA_ADVISOR_BLOCK") { $inBlock = $true; continue }
            if ($l -eq "# END ACA_ADVISOR_BLOCK")   { $inBlock = $false; continue }
            if (-not $inBlock) { $clean += $l }
        }
        if ($domains -and $domains.Count -gt 0) {
            $clean += "# BEGIN ACA_ADVISOR_BLOCK"
            foreach ($d in $domains) {
                $dom = ([string]$d).Trim().ToLower() -replace '^https?://', '' -replace '/.*$', ''
                if ($dom -and $dom -match '^[a-z0-9.-]+\.[a-z]{2,}$') {
                    $clean += "127.0.0.1 $dom"
                    if (-not $dom.StartsWith("www.")) { $clean += "127.0.0.1 www.$dom" }
                }
            }
            $clean += "# END ACA_ADVISOR_BLOCK"
        }
        Set-Content -Path $hostsPath -Value $clean -Encoding ASCII -Force -ErrorAction SilentlyContinue
    } catch {}
}

Write-DlpLog "=== Iniciando ACA Advisor DLP & Screenshot Monitor ($Computer) ==="

$knownUsb       = @{}
$seenPrintJobs  = @{}
$lastClipHash   = ""
$lastImgHash    = ""
$lastHostsSig   = ""
$lastPolicySync = (Get-Date).AddMinutes(-10)
$lastScreenshot = (Get-Date).AddMinutes(-10)

$activeToken    = ""
$activeApiUrl   = "http://192.168.0.155:3001/api/v1"
$activeLoginUrl = "http://192.168.0.155:3004/api/v3/employee/login"
$activeEmail    = ""
$policy = @{
    usb_detec      = $true
    usb_block      = $false
    clip_detec     = $true
    clip_block     = $false
    print_detec    = $true
    print_block    = $false
    web_block      = $false
    app_block      = $false
    screenshots    = $true
    ss_period_sec  = 60
    blocked_webs   = @()
    blocked_apps   = @()
}

# Inicializar discos USB actuales para no disparar falsos positivos al arrancar
try {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | ForEach-Object {
        $knownUsb[$_.DeviceID] = @{ label = $_.VolumeName; serial = $_.VolumeSerialNumber }
    }
} catch {}

while ($true) {
    try {
        $now = Get-Date

        # 1. Sincronizar token y politicas DLP desde el servidor cada 60 segundos
        if (($now - $lastPolicySync).TotalSeconds -ge 60 -or -not $activeToken) {
            $auth = Get-AgentAuth
            $activeApiUrl   = $auth.apiUrl
            $activeLoginUrl = $auth.loginUrl

            # Purgar trabajos de impresion antiguos (>24h) para evitar crecimiento de memoria
            foreach ($oldJob in @($seenPrintJobs.Keys)) {
                if (($now - $seenPrintJobs[$oldJob]).TotalHours -ge 24) {
                    $seenPrintJobs.Remove($oldJob)
                }
            }

            if ($auth.email -and $auth.password) {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    $loginHeaders = @{
                        "Client-Device" = $Computer
                        "X-Device-Id"   = $DeviceId
                    }
                    $loginBody = @{ email = $auth.email; password = $auth.password; macId = $DeviceId } | ConvertTo-Json -Compress
                    $res = Invoke-RestMethod -Uri $activeLoginUrl -Method Post -Headers $loginHeaders -Body $loginBody -ContentType "application/json" -TimeoutSec 12 -ErrorAction Stop
                    if ($res -and $res.accessToken) {
                        $activeToken = [string]$res.accessToken
                        $activeEmail = $auth.email
                        $lastPolicySync = $now

                        # Sincronizar token fresco hacia HKCU para mantener aca-agent.exe autenticado tras reinicios
                        if ($auth.mode -eq "office") {
                            try {
                                $hkcuAuth = "HKCU:\Software\screen\empm\auth"
                                if (-not (Test-Path $hkcuAuth)) { New-Item -Path $hkcuAuth -Force | Out-Null }
                                Set-ItemProperty -Path $hkcuAuth -Name "token" -Value $activeToken -Force
                            } catch {}
                        }

                        # Extraer politicas DLP en vivo (emp_desktop retorna "settings")
                        $st = if ($res.settings) { $res.settings } else { $res.setting }
                        if ($st) {
                            $dlp = $st.dlpFeatures
                            $feat = $st.features
                            if ($dlp) {
                                $policy.usb_detec   = ([string]$dlp.usb_detec -ne "0")
                                $policy.usb_block   = ([string]$dlp.usb_block -eq "1" -or $st.usbDisable -eq 1)
                                $policy.clip_detec  = ([string]$dlp.clip_detec -ne "0")
                                $policy.clip_block  = ([string]$dlp.clip_block -eq "1")
                                $policy.web_block   = ([string]$dlp.web_block -eq "1")
                                $policy.app_block   = ([string]$dlp.app_block -eq "1")
                            }
                            $policy.print_detec = ([string]$st.print_detection -ne "0")
                            $policy.print_block = ([string]$st.print_blocking -eq "1")
                            if ($feat) {
                                $policy.screenshots = ([string]$feat.screenshots -ne "0")
                            }
                            $ssSec = 60
                            if ($st.screenshot -and $st.screenshot.screenshotPeriodSec) {
                                $ssSec = [int]$st.screenshot.screenshotPeriodSec
                            } elseif ($st.screenshotPeriodSec) {
                                $ssSec = [int]$st.screenshotPeriodSec
                            }
                            if ($ssSec -lt 20) { $ssSec = 20 }
                            $policy.ss_period_sec = $ssSec

                            # Listas de bloqueo web y apps
                            $webs = @()
                            if ($st.tracking -and $st.tracking.domain -and $st.tracking.domain.websiteBlockList) {
                                $webs = @($st.tracking.domain.websiteBlockList)
                            }
                            $policy.blocked_webs = $webs

                            $apps = @()
                            if ($st.tracking -and $st.tracking.domain -and $st.tracking.domain.appBlockList) {
                                if ($st.tracking.domain.appBlockList -is [string]) {
                                    $apps = ($st.tracking.domain.appBlockList -split ',') | Where-Object { $_.Trim() -ne '' }
                                } else {
                                    $apps = @($st.tracking.domain.appBlockList)
                                }
                            }
                            $policy.blocked_apps = $apps

                            # Aplicar bloqueo USBSTOR y hosts si cambio
                            Set-UsbBlockState $policy.usb_block
                            $hostsList = if ($policy.web_block) { $policy.blocked_webs } else { @() }
                            $hostsSig = ($hostsList -join ',')
                            if ($hostsSig -ne $lastHostsSig) {
                                Apply-WebsiteBlockList $hostsList
                                $lastHostsSig = $hostsSig
                            }
                        }
                    }
                } catch {
                    Write-DlpLog "Error sincronizando politicas: $_"
                    $lastPolicySync = $now.AddSeconds(-40)
                }
            } elseif ($auth.token) {
                $activeToken = $auth.token
                $lastPolicySync = $now
            } else {
                Start-Sleep -Seconds 5
                continue
            }
        }

        if (-not $activeToken) {
            Start-Sleep -Seconds 5
            continue
        }

        # 2. Deteccion de dispositivos USB (Insertado = type 2, Retirado = type 3, Bloqueado = type 4)
        if ($policy.usb_detec -or $policy.usb_block) {
            $currentUsb = @{}
            try {
                Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | ForEach-Object {
                    $devId = $_.DeviceID
                    $currentUsb[$devId] = @{
                        label  = if ($_.VolumeName) { $_.VolumeName } else { "Dispositivo USB" }
                        serial = if ($_.VolumeSerialNumber) { $_.VolumeSerialNumber } else { "N/A" }
                        sizeGB = if ($_.Size) { [math]::Round($_.Size / 1GB, 2) } else { 0 }
                    }
                    if (-not $knownUsb.ContainsKey($devId)) {
                        $info = $currentUsb[$devId]
                        $evType = if ($policy.usb_block) { "4" } else { "2" }
                        $evTitle = if ($policy.usb_block) { "USB Blocked" } else { "USB Inserted" }
                        $descObj = @{
                            event  = $evTitle
                            drive  = $devId
                            label  = $info.label
                            serial = $info.serial
                            size   = "$($info.sizeGB) GB"
                        } | ConvertTo-Json -Compress
                        Send-DlpEvent $activeApiUrl $activeToken $evType $evTitle $descObj
                    }
                }
                foreach ($oldDev in @($knownUsb.Keys)) {
                    if (-not $currentUsb.ContainsKey($oldDev)) {
                        $oldInfo = $knownUsb[$oldDev]
                        $descObj = @{
                            event  = "USB Removed"
                            drive  = $oldDev
                            label  = $oldInfo.label
                            serial = $oldInfo.serial
                        } | ConvertTo-Json -Compress
                        Send-DlpEvent $activeApiUrl $activeToken "3" "USB Removed" $descObj
                    }
                }
                $knownUsb = $currentUsb
            } catch {}
        }

        # 3. Deteccion de Portapapeles (Texto e Imagenes = type 10) + Bloqueo
        if ($policy.clip_detec -or $policy.clip_block) {
            try {
                if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                    $clipText = [System.Windows.Forms.Clipboard]::GetText()
                    if ($clipText -and $clipText.Trim().Length -gt 0) {
                        $trimmed = $clipText.Trim()
                        if ($trimmed.Length -gt 2000) { $trimmed = $trimmed.Substring(0, 2000) + "..." }
                        $h = Get-Sha256 $trimmed
                        if ($h -ne $lastClipHash) {
                            $lastClipHash = $h
                            if ($policy.clip_block) {
                                [System.Windows.Forms.Clipboard]::Clear()
                                Send-DlpEvent $activeApiUrl $activeToken "10" "Clipboard Blocked" "Clipboard Data : [BLOQUEADO POR POLITICA DLP]"
                            } else {
                                Send-DlpEvent $activeApiUrl $activeToken "10" "Clipboard" "Clipboard Data : $trimmed"
                            }
                        }
                    }
                } elseif ([System.Windows.Forms.Clipboard]::ContainsImage()) {
                    $img = [System.Windows.Forms.Clipboard]::GetImage()
                    if ($img) {
                        $tw = $img.Width
                        $th = $img.Height
                        if ($tw -gt 1024) {
                            $ratio = 1024.0 / [double]$tw
                            $tw = 1024
                            $th = [int][math]::Round($th * $ratio)
                        }
                        $bmp = New-Object System.Drawing.Bitmap($tw, $th)
                        $g = [System.Drawing.Graphics]::FromImage($bmp)
                        $g.DrawImage($img, 0, 0, $tw, $th)
                        $g.Dispose()
                        $img.Dispose()
                        $ms = New-Object System.IO.MemoryStream
                        $bmp.Save($ms, $jpegCodec, $encParams)
                        $bmp.Dispose()
                        $b64 = [Convert]::ToBase64String($ms.ToArray())
                        $ms.Dispose()
                        $ih = Get-Sha256 $b64
                        if ($ih -ne $lastImgHash) {
                            $lastImgHash = $ih
                            if ($policy.clip_block) {
                                [System.Windows.Forms.Clipboard]::Clear()
                            }
                            Send-DlpEvent $activeApiUrl $activeToken "10" "Clipboard Image" "Clipboard Image Data : $b64"
                        }
                    }
                }
            } catch {}
        }

        # 4. Deteccion de Impresiones (Print Logs = type 11) + Bloqueo
        if ($policy.print_detec -or $policy.print_block) {
            try {
                Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue | ForEach-Object {
                    $jid = "$($_.Name)_$($_.JobId)"
                    if (-not $seenPrintJobs.ContainsKey($jid)) {
                        $seenPrintJobs[$jid] = $now
                        $printer = ($_.Name -split ',')[0]
                        $doc     = if ($_.Document) { $_.Document } else { "Documento sin titulo" }
                        $pages   = if ($_.TotalPages) { $_.TotalPages } else { 1 }
                        $owner   = if ($_.Owner) { $_.Owner } else { $env:USERNAME }
                        if ($policy.print_block) {
                            try { Remove-CimInstance -InputObject $_ -ErrorAction SilentlyContinue } catch {}
                            Send-DlpEvent $activeApiUrl $activeToken "11" "Print Blocked" "Impresora: $printer | Documento: $doc | Paginas: $pages | Usuario: $owner | Estado: BLOQUEADO"
                        } else {
                            Send-DlpEvent $activeApiUrl $activeToken "11" "Print Job" "Impresora: $printer | Documento: $doc | Paginas: $pages | Usuario: $owner"
                        }
                    }
                }
            } catch {}
        }

        # 5. Bloqueo de aplicaciones (app_block)
        if ($policy.app_block -and $policy.blocked_apps.Count -gt 0) {
            foreach ($appName in $policy.blocked_apps) {
                $cleanName = ([string]$appName).Trim() -replace '\.exe$', ''
                if ($cleanName) {
                    Get-Process -Name $cleanName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # 6. Capturas de pantalla periodicas (/api/v1/desktop/upload-screenshots)
        if ($policy.screenshots -and (($now - $lastScreenshot).TotalSeconds -ge $policy.ss_period_sec)) {
            $lastScreenshot = $now
            Upload-PeriodicScreenshot $activeApiUrl $activeToken
        }
    } catch {
        Write-DlpLog "Error en ciclo principal DLP: $_"
    }

    Start-Sleep -Seconds 2
}
