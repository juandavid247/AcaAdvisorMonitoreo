# ==============================================================================
# ACA ADVISOR S.A.S. - CONFIGURACION INTEGRAL DEL AGENTE CORPORATIVO WINDOWS v3.0.6
# Soporta modo Sigilo ("office") y modo Visible ("personal")
# ==============================================================================
param(
    [string]$ServerHost = "192.168.0.155",
    [string]$OrgId = "OjUpRAB",
    [ValidateSet("office", "personal")]
    [string]$Mode = "office",
    [switch]$UseHttps,
    [string]$EnrollmentKey = ""
)

$BaseProto    = if ($UseHttps) { "https" } else { "http" }
$WsProto      = if ($UseHttps) { "wss" } else { "ws" }
$ApiBaseUrl   = if ($UseHttps) { "https://${ServerHost}/logs/api/v1" } else { "http://${ServerHost}:3001/api/v1" }
$LoginBaseUrl = if ($UseHttps) { "https://${ServerHost}/desktop/api/v3" } else { "http://${ServerHost}:3004/api/v3" }
$RealtimeUrl  = if ($UseHttps) { "wss://${ServerHost}/ws/realtime" } else { "ws://${ServerHost}:3003" }
$DownloadBase = if ($UseHttps) { "https://${ServerHost}/downloads" } else { "http://${ServerHost}:8081/downloads" }
$PanelUrl     = if ($UseHttps) { "https://${ServerHost}/admin/live-monitoring" } else { "http://${ServerHost}:8081/admin/live-monitoring" }
$CacheBust    = "v=306"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ACA Advisor Agent v3.0.6 - Configurador Oficial ($Mode)"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    ACA ADVISOR S.A.S. - AGENTE CORPORATIVO WINDOWS       " -ForegroundColor Cyan
Write-Host "              Version 3.0.6 | Modo: $Mode                 " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$AgentCryptoPassword = "43d7dbcf81bad521552d1b59e619cced:ede717306619e874100560153a96ecc3"
$AgentEmail = ""
$AgentAccessToken = ""
$AgentIdentifier = $OrgId

# 1. Comprobacion y elevacion de permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Solicitando permisos de Administrador..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            $extraArgs = ""
            if ($UseHttps) { $extraArgs += " -UseHttps" }
            if ($EnrollmentKey) { $extraArgs += " -EnrollmentKey `"$EnrollmentKey`"" }
            Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ServerHost `"$ServerHost`" -OrgId `"$OrgId`" -Mode `"$Mode`"$extraArgs" -Verb RunAs
        } else {
            Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"& { irm '${DownloadBase}/fix-agent.ps1?${CacheBust}' | iex }`"" -Verb RunAs
        }
        exit
    } catch {
        Write-Host "[-] Se requieren permisos de Administrador para configurar el agente." -ForegroundColor Red
        exit 1
    }
}

# 2. Deteccion de identidad unica de la maquina (MachineGuid + COMPUTERNAME)
$computerName = $env:COMPUTERNAME
$systemUser = $env:USERNAME
if (-not $systemUser -or $systemUser -eq "SYSTEM") {
    $systemUser = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
    if ($systemUser -and $systemUser.Contains('\')) {
        $systemUser = $systemUser.Split('\')[1]
    }
}
if (-not $systemUser) { $systemUser = "Usuario" }

$activeMac = ""
try {
    $mguid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -ErrorAction SilentlyContinue).MachineGuid
    if ($mguid) { $activeMac = $mguid.Trim().ToLower() }
} catch {}

if (-not $activeMac) {
    try {
        $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        if ($adapter -and $adapter.MacAddress) {
            $activeMac = ($adapter.MacAddress -replace '-', ':').ToUpper()
        }
    } catch {}
}

if (-not $activeMac) {
    try {
        $macRaw = (getmac /fo csv /nh 2>$null | Select-Object -First 1).Split(',')[0].Trim('"')
        if ($macRaw) { $activeMac = ($macRaw -replace '-', ':').ToUpper() }
    } catch {}
}
if (-not $activeMac) {
    $activeMac = "00:50:56:C0:00:08"
}

Write-Host "`n[*] Datos del equipo detectados:" -ForegroundColor Cyan
Write-Host "    - Computador: $computerName" -ForegroundColor White
Write-Host "    - Usuario:    $systemUser" -ForegroundColor White
Write-Host "    - MachineID:  $activeMac" -ForegroundColor White
Write-Host "    - Modo:       $Mode" -ForegroundColor White

# 3. Auto-registro unico por equipo y pre-autenticacion en servidor ACA ADVISOR (modo office)
if ($Mode -eq "office") {
    $AgentEmail = "$($activeMac)_@$($systemUser).$OrgId"
    Write-Host "`n[*] Registrando y autenticando equipo en servidor central ($ServerHost)..." -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $regPayload = @{
            macId          = $activeMac
            organizationId = $OrgId
            username       = $systemUser
            computerName   = $computerName
            firstname      = "$computerName -"
            lastname       = $systemUser
        } | ConvertTo-Json

        $regHeaders = @{
            "Client-Device" = $computerName
            "X-Device-Id"   = $activeMac
        }
        if ($EnrollmentKey) { $regHeaders["X-Enrollment-Key"] = $EnrollmentKey }

        $regRes = Invoke-RestMethod -Uri "${LoginBaseUrl}/auth/register" -Method Post -Headers $regHeaders -Body $regPayload -ContentType "application/json" -TimeoutSec 12 -ErrorAction Stop
        if ($regRes -and $regRes.code -eq 200) {
            if ($regRes.data -and $regRes.data.email) {
                $AgentEmail = [string]$regRes.data.email
            } elseif ($regRes.email) {
                $AgentEmail = [string]$regRes.email
            }
            if ($regRes.data -and $regRes.data.crypto_password) {
                $AgentCryptoPassword = [string]$regRes.data.crypto_password
            } elseif ($regRes.crypto_password) {
                $AgentCryptoPassword = [string]$regRes.crypto_password
            }
            Write-Host "  [+] Equipo vinculado en servidor (1 usuario por PC): $AgentEmail" -ForegroundColor Green
        } else {
            Write-Host "  [!] El servidor respondio: $($regRes | ConvertTo-Json -Compress)" -ForegroundColor Yellow
        }

        # Pre-login inmediato para guardar token fresco en Registro ANTES de arrancar aca-agent.exe
        $loginPayload = @{
            email    = $AgentEmail
            password = $AgentCryptoPassword
            macId    = $activeMac
        } | ConvertTo-Json -Compress
        $loginRes = Invoke-RestMethod -Uri "${LoginBaseUrl}/employee/login" -Method Post -Headers $regHeaders -Body $loginPayload -ContentType "application/json" -TimeoutSec 12 -ErrorAction Stop
        if ($loginRes -and $loginRes.accessToken) {
            $AgentAccessToken = [string]$loginRes.accessToken
            if ($loginRes.identifier) { $AgentIdentifier = [string]$loginRes.identifier }
            Write-Host "  [+] Pre-autenticacion exitosa (user_id=$($loginRes.user_id), token listo para aca-agent.exe)." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [!] Nota sobre registro/pre-login: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[*] Modo visible (personal): el empleado iniciara sesion desde la interfaz del agente." -ForegroundColor Cyan
    try {
        if (Test-Path "HKCU:\Software\screen\empm\auth") {
            $existingAuth = Get-ItemProperty -Path "HKCU:\Software\screen\empm\auth" -ErrorAction SilentlyContinue
            if ($existingAuth.email) { $AgentEmail = [string]$existingAuth.email }
            if ($existingAuth.crypto_password) { $AgentCryptoPassword = [string]$existingAuth.crypto_password }
            if ($existingAuth.token) { $AgentAccessToken = [string]$existingAuth.token }
        }
    } catch {}
}

# 4. Agregar exclusiones oficiales en Windows Defender
Write-Host "`n[1/6] Configurando exclusiones en Windows Defender..." -ForegroundColor Yellow
$CandidateDirs = @(
    "C:\Program Files\ACA Advisor Agent",
    "C:\Program Files (x86)\ACA Advisor Agent",
    "C:\Program Files\Empmonitor",
    "C:\Program Files (x86)\Empmonitor",
    "C:\Program Files\EmpMonitor\EmpMonitor"
)

if ($PSScriptRoot -and ($CandidateDirs -notcontains $PSScriptRoot)) {
    $CandidateDirs = @($PSScriptRoot) + $CandidateDirs
}

foreach ($dir in $CandidateDirs) {
    try {
        Add-MpPreference -ExclusionPath $dir -ErrorAction SilentlyContinue
        Write-Host "  [+] Exclusion de carpeta: $dir" -ForegroundColor Green
    } catch {}
}
try {
    Add-MpPreference -ExclusionProcess "aca-agent.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "empmonitor.exe" -ErrorAction SilentlyContinue
    Write-Host "  [+] Exclusion de procesos: aca-agent.exe, empmonitor.exe" -ForegroundColor Green
} catch {}

# 5. Cerrar instancias previas (launcher, streamer, DLP y binario principal)
Write-Host "`n[2/6] Cerrando instancias anteriores del agente..." -ForegroundColor Yellow
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and (
                $_.CommandLine -like '*agent-launcher.ps1*' -or
                $_.CommandLine -like '*live-stream.ps1*' -or
                $_.CommandLine -like '*dlp-monitor.ps1*'
            )
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {}
Stop-Process -Name "aca-agent","empmonitor" -Force -ErrorAction SilentlyContinue
cmd.exe /c "taskkill /f /im aca-agent.exe /im empmonitor.exe 2>nul" | Out-Null
Start-Sleep -Seconds 2

# Localizar carpetas activas de instalacion
$activeDirs = @()
foreach ($dir in $CandidateDirs) {
    if ((Test-Path "$dir\aca-agent.exe") -or (Test-Path "$dir\empmonitor.exe")) {
        $activeDirs += $dir
    }
}

# Si no existe ninguna, descargar e instalar segun el modo
if ($activeDirs.Count -eq 0) {
    $primaryDir = "C:\Program Files\ACA Advisor Agent"
    $installerName = if ($Mode -eq "personal") { "ACA_Advisor_Agent_Visible_Setup.exe" } else { "ACA_Advisor_Agent_Setup.exe" }
    Write-Host "[*] No se detecto instalacion previa. Descargando $installerName..." -ForegroundColor Cyan
    $installerPath = "$env:TEMP\$installerName"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "${DownloadBase}/${installerName}?${CacheBust}" -OutFile $installerPath -UseBasicParsing
        Write-Host "  [+] Instalador descargado. Ejecutando instalacion silenciosa..." -ForegroundColor Green
        Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait
        Start-Sleep -Seconds 3
        if (Test-Path $primaryDir) { $activeDirs += $primaryDir }
    } catch {
        Write-Host "[-] Error al descargar el instalador: $_" -ForegroundColor Red
    }
}

if ($activeDirs.Count -eq 0) {
    Write-Host "[-] No se encontro el agente en ninguna ruta estandar." -ForegroundColor Red
    exit 1
}

# 6. Configurar y actualizar cada directorio encontrado (Binario v3.0.5 + Icono + Permisos + Config)
Write-Host "`n[3/6] Actualizando binario, icono, permisos y configuracion..." -ForegroundColor Yellow
$configJson = @"
{
  "id": "$OrgId",
  "mode": "$Mode",
  "api": "$ApiBaseUrl",
  "login": "$LoginBaseUrl",
  "pipeline": "$ApiBaseUrl",
  "realtime": "$RealtimeUrl",
  "updates": "$LoginBaseUrl"
}
"@

$shouldRefreshRemote = (-not $PSCommandPath)
$lockFiles = @("planExpiryFile.txt", "EmployeeTimestamp.txt", "dataLog.txt", "usbInsLogs.txt", "usbRemLogs.txt", "local_db20.db", "local_db20.db-journal", "temp_db20.db", "temp_db20.db-journal")

foreach ($targetDir in $activeDirs) {
    Write-Host "  [*] Procesando: $targetDir" -ForegroundColor Cyan

    # Si se ejecuta remotamente (irm | iex), actualizar aca-agent.exe (con icono .ico embebido) y aca-advisor.ico en sitio
    if ($shouldRefreshRemote) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $tmpExe = Join-Path $env:TEMP "aca-agent-v305.exe"
            Invoke-WebRequest -Uri "${DownloadBase}/aca-agent.exe?${CacheBust}" -OutFile $tmpExe -UseBasicParsing -ErrorAction Stop
            if ((Test-Path $tmpExe) -and ((Get-Item $tmpExe).Length -gt 1000000)) {
                $destAca = Join-Path $targetDir "aca-agent.exe"
                $destEmp = Join-Path $targetDir "empmonitor.exe"
                Copy-Item -Path $tmpExe -Destination $destAca -Force
                if (Test-Path $destEmp) { Copy-Item -Path $tmpExe -Destination $destEmp -Force }
                Remove-Item -Path $tmpExe -Force -ErrorAction SilentlyContinue
                Write-Host "    [+] aca-agent.exe actualizado a v3.0.5 (con logo aca-advisor.ico embebido)." -ForegroundColor Green
            }
        } catch {
            Write-Host "    [!] No se pudo actualizar aca-agent.exe desde servidor: $_" -ForegroundColor Yellow
        }

        try {
            $destIco = Join-Path $targetDir "aca-advisor.ico"
            Invoke-WebRequest -Uri "${DownloadBase}/aca-advisor.ico?${CacheBust}" -OutFile $destIco -UseBasicParsing -ErrorAction Stop
            Write-Host "    [+] aca-advisor.ico actualizado." -ForegroundColor Green
        } catch {}
    }

    # Permisos endurecidos pero 100% compatibles con SQLite para usuarios estandar:
    # - Subdirectorios de librerias heredan solo RX; archivos de runtime nuevos en raiz (.db/.db-journal/.txt) heredan (OI)(NP)M
    # - Binarios (.exe/.dll), scripts (.ps1) y configs/ se bloquean explicitamente con /inheritance:r + Users:RX/R
    cmd.exe /c "icacls `"$targetDir`" /inheritance:r /grant:r `"*S-1-5-18:(OI)(CI)F`" /grant:r `"*S-1-5-32-544:(OI)(CI)F`" /grant:r `"*S-1-5-32-545:(CI)RX`" /grant `"*S-1-5-32-545:(OI)(NP)M`" /C /Q 2>nul"

    $failedSsDir = Join-Path $targetDir "failed_screenshots"
    if (-not (Test-Path $failedSsDir)) { New-Item -ItemType Directory -Path $failedSsDir -Force | Out-Null }
    cmd.exe /c "icacls `"$failedSsDir`" /inheritance:r /grant:r `"*S-1-5-18:(OI)(CI)F`" /grant:r `"*S-1-5-32-544:(OI)(CI)F`" /grant:r `"*S-1-5-32-545:(OI)(CI)M`" /C /Q 2>nul"

    $logsDir = Join-Path $targetDir "logs"
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    cmd.exe /c "icacls `"$logsDir`" /inheritance:r /grant:r `"*S-1-5-18:(OI)(CI)F`" /grant:r `"*S-1-5-32-544:(OI)(CI)F`" /grant:r `"*S-1-5-32-545:(OI)(CI)M`" /C /Q 2>nul"

    # Limpiar archivos de bloqueo y DBs residuales creadas por Admin para que el usuario logueado escriba sin SQLITE_READONLY
    foreach ($lf in $lockFiles) {
        $fPath = Join-Path $targetDir $lf
        if (Test-Path $fPath) {
            Remove-Item -Path $fPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Escribir config.js y config.json (protegidos contra escritura de usuarios estandar)
    $configsFolder = Join-Path $targetDir "configs"
    if (-not (Test-Path $configsFolder)) { New-Item -ItemType Directory -Path $configsFolder -Force | Out-Null }
    cmd.exe /c "icacls `"$configsFolder`" /inheritance:r /grant:r `"*S-1-5-18:(OI)(CI)F`" /grant:r `"*S-1-5-32-544:(OI)(CI)F`" /grant:r `"*S-1-5-32-545:(OI)(CI)R`" /C /Q 2>nul"

    $configFile1 = Join-Path $configsFolder "config.js"
    $configFile2 = Join-Path $configsFolder "config.json"
    if (Test-Path $configFile1) { try { (Get-Item $configFile1).IsReadOnly = $false } catch {} }
    if (Test-Path $configFile2) { try { (Get-Item $configFile2).IsReadOnly = $false } catch {} }

    [System.IO.File]::WriteAllText($configFile1, $configJson, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($configFile2, $configJson, [System.Text.Encoding]::UTF8)
    try { (Get-Item $configFile1).IsReadOnly = $true } catch {}
    try { (Get-Item $configFile2).IsReadOnly = $true } catch {}
    Write-Host "    [+] config.js y config.json aplicados (mode=$Mode)." -ForegroundColor Green

    # Asegurar plugins de plataforma Qt
    $qtConfPath = Join-Path $targetDir "qt.conf"
    "[Paths]`r`nPrefix=.`r`nPlugins=plugins" | Out-File -FilePath $qtConfPath -Encoding ascii -Force
    $pluginsPlatforms = Join-Path $targetDir "plugins\platforms"
    $directPlatforms = Join-Path $targetDir "platforms"
    if ((Test-Path $pluginsPlatforms) -and -not (Test-Path $directPlatforms)) {
        Copy-Item -Path $pluginsPlatforms -Destination $directPlatforms -Recurse -Force
    }
}

# 7. Configurar el Registro de Windows (QSettings de Qt: screen\empm y Empmonitor) en TODOS los perfiles
Write-Host "`n[4/6] Configurando Registro de Windows (QSettings, credenciales y token fresco)..." -ForegroundColor Yellow

$userSids = @()
try {
    $userSids = Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' } |
        ForEach-Object { $_.PSChildName }
} catch {}

$regRoots = @(
    "HKCU:\Software\screen\empm",
    "HKLM:\Software\screen\empm",
    "HKCU:\Software\Empmonitor",
    "HKLM:\Software\Empmonitor",
    "HKCU:\Software\EmpMonitor\EmpMonitor",
    "HKLM:\Software\EmpMonitor\EmpMonitor"
)

foreach ($sid in $userSids) {
    $regRoots += "Registry::HKEY_USERS\$sid\Software\screen\empm"
    $regRoots += "Registry::HKEY_USERS\$sid\Software\Empmonitor"
    $regRoots += "Registry::HKEY_USERS\$sid\Software\EmpMonitor\EmpMonitor"
}

foreach ($root in $regRoots) {
    try {
        if (-not (Test-Path $root)) { New-Item -Path $root -Force | Out-Null }

        Set-ItemProperty -Path $root -Name "api" -Value "$ApiBaseUrl" -Force
        Set-ItemProperty -Path $root -Name "pipeline" -Value "$ApiBaseUrl" -Force
        Set-ItemProperty -Path $root -Name "realtime" -Value "$RealtimeUrl" -Force
        Set-ItemProperty -Path $root -Name "login" -Value "$LoginBaseUrl" -Force
        Set-ItemProperty -Path $root -Name "updates" -Value "$LoginBaseUrl" -Force
        Set-ItemProperty -Path $root -Name "backend_base" -Value "$ApiBaseUrl" -Force
        Set-ItemProperty -Path $root -Name "backend_base_login" -Value "$LoginBaseUrl" -Force
        Set-ItemProperty -Path $root -Name "update_base_url" -Value "$LoginBaseUrl" -Force
        Set-ItemProperty -Path $root -Name "organization_id" -Value "$OrgId" -Force
        Set-ItemProperty -Path $root -Name "identifier" -Value "$AgentIdentifier" -Force

        # Credenciales y token fresco (evita 403 al primer arranque y tras reinicios)
        if ($Mode -eq "office" -and $AgentEmail) {
            $authPath = "$root\auth"
            if (-not (Test-Path $authPath)) { New-Item -Path $authPath -Force | Out-Null }
            Set-ItemProperty -Path $authPath -Name "email" -Value $AgentEmail -Force
            Set-ItemProperty -Path $authPath -Name "crypto_password" -Value $AgentCryptoPassword -Force
            if ($AgentAccessToken) {
                Set-ItemProperty -Path $authPath -Name "token" -Value $AgentAccessToken -Force
            }
        }

        $fromRemote = "$root\appSettings\from_remote"
        if (-not (Test-Path $fromRemote)) { New-Item -Path $fromRemote -Force | Out-Null }
        Set-ItemProperty -Path $fromRemote -Name "account_type" -Value "$Mode" -Force
        Set-ItemProperty -Path $fromRemote -Name "screenshotPeriodSec" -Value 20 -Type DWord -Force
        Set-ItemProperty -Path $fromRemote -Name "ADUserInfoSendPerSec" -Value 60 -Type DWord -Force

        $appSettings = "$root\appSettings"
        if (-not (Test-Path $appSettings)) { New-Item -Path $appSettings -Force | Out-Null }
        Set-ItemProperty -Path $appSettings -Name "screenshotQuality" -Value 82 -Type DWord -Force
        Set-ItemProperty -Path $appSettings -Name "dataSendingPeriodSec" -Value 30 -Type DWord -Force
        Set-ItemProperty -Path $appSettings -Name "mode" -Value "$Mode" -Force

        $trackingMode = "$root\appSettings\data"
        if (-not (Test-Path $trackingMode)) { New-Item -Path $trackingMode -Force | Out-Null }
        Set-ItemProperty -Path $trackingMode -Name "trackingMode" -Value "unlimited" -Force

        $features = "$root\appSettings\data\features"
        if (-not (Test-Path $features)) { New-Item -Path $features -Force | Out-Null }
        Set-ItemProperty -Path $features -Name "screenshots" -Value "1" -Force
        Set-ItemProperty -Path $features -Name "screencast" -Value "1" -Force
        Set-ItemProperty -Path $features -Name "realTimeTrack" -Value "1" -Force
        Set-ItemProperty -Path $features -Name "application_usage" -Value "1" -Force
        Set-ItemProperty -Path $features -Name "keystrokes" -Value "1" -Force
        Set-ItemProperty -Path $features -Name "web_usage" -Value "1" -Force
        Set-ItemProperty -Path $features -Name "block_websites" -Value "0" -Force
    } catch {}
}
Write-Host "  [+] Registro configurado en HKCU, HKLM y perfiles de usuario." -ForegroundColor Green

# 8. Actualizar scripts auxiliares (Launcher Watchdog, Live Stream y DLP)
$mainDir = $activeDirs[0]
$exePath = Join-Path $mainDir "aca-agent.exe"
if (-not (Test-Path $exePath)) { $exePath = Join-Path $mainDir "empmonitor.exe" }

$launcherScriptPath = Join-Path $mainDir "agent-launcher.ps1"
$streamScriptPath   = Join-Path $mainDir "live-stream.ps1"
$dlpScriptPath      = Join-Path $mainDir "dlp-monitor.ps1"
$streamConfigPath   = Join-Path (Join-Path $mainDir "configs") "stream.json"

if ($shouldRefreshRemote -or -not (Test-Path $launcherScriptPath)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "${DownloadBase}/agent-launcher.ps1?${CacheBust}" -OutFile $launcherScriptPath -UseBasicParsing -ErrorAction Stop
        Write-Host "  [+] Modulo Launcher Watchdog (agent-launcher.ps1) actualizado." -ForegroundColor Green
    } catch {
        Write-Host "  [!] No se pudo descargar agent-launcher.ps1: $_" -ForegroundColor Yellow
    }
}
if ($shouldRefreshRemote -or -not (Test-Path $streamScriptPath)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "${DownloadBase}/live-stream.ps1?${CacheBust}" -OutFile $streamScriptPath -UseBasicParsing -ErrorAction Stop
        Write-Host "  [+] Modulo Live Screen (live-stream.ps1) actualizado." -ForegroundColor Green
    } catch {
        Write-Host "  [!] No se pudo descargar live-stream.ps1: $_" -ForegroundColor Yellow
    }
}
if ($shouldRefreshRemote -or -not (Test-Path $dlpScriptPath)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "${DownloadBase}/dlp-monitor.ps1?${CacheBust}" -OutFile $dlpScriptPath -UseBasicParsing -ErrorAction Stop
        Write-Host "  [+] Modulo DLP & Capturas (dlp-monitor.ps1) actualizado." -ForegroundColor Green
    } catch {
        Write-Host "  [!] No se pudo descargar dlp-monitor.ps1: $_" -ForegroundColor Yellow
    }
}

try {
    $streamCfg = @{
        server       = $ServerHost
        orgId        = $OrgId
        deviceId     = $activeMac
        computerName = $computerName
        useHttps     = [bool]$UseHttps
        apiUrl       = $ApiBaseUrl
        loginUrl     = "${LoginBaseUrl}/employee/login"
        realtimeUrl  = $RealtimeUrl
        mode         = $Mode
        email        = $AgentEmail
        password     = if ($AgentEmail) { $AgentCryptoPassword } else { "" }
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($streamConfigPath, $streamCfg, [System.Text.Encoding]::UTF8)
    Write-Host "  [+] Configuracion stream.json generada (con MachineID=$activeMac)." -ForegroundColor Green
} catch {
    Write-Host "  [!] Error escribiendo stream.json: $_" -ForegroundColor Yellow
}

# Endurecer permisos en ejecutables, DLLs, icono, scripts y configuraciones
foreach ($protectedFile in @(
    $exePath,
    (Join-Path $mainDir "aca-agent.exe"),
    (Join-Path $mainDir "empmonitor.exe"),
    (Join-Path $mainDir "aca-advisor.ico"),
    (Join-Path $mainDir "qt.conf"),
    $launcherScriptPath,
    $streamScriptPath,
    $dlpScriptPath,
    (Join-Path $mainDir "register.ps1")
)) {
    if (Test-Path $protectedFile) {
        cmd.exe /c "icacls `"$protectedFile`" /inheritance:r /grant:r `"*S-1-5-18:F`" /grant:r `"*S-1-5-32-544:F`" /grant:r `"*S-1-5-32-545:RX`" /C /Q 2>nul"
    }
}
Get-ChildItem -Path $mainDir -Filter "*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
    cmd.exe /c "icacls `"$($_.FullName)`" /inheritance:r /grant:r `"*S-1-5-18:F`" /grant:r `"*S-1-5-32-544:F`" /grant:r `"*S-1-5-32-545:RX`" /C /Q 2>nul"
}
if (Test-Path $streamConfigPath) {
    cmd.exe /c "icacls `"$streamConfigPath`" /inheritance:r /grant:r `"*S-1-5-18:F`" /grant:r `"*S-1-5-32-544:F`" /grant:r `"*S-1-5-32-545:R`" /C /Q 2>nul"
}

# Limpiar entradas legacy duplicadas y crear autoarranque UNICO (Launcher Watchdog con WorkingDirectory y delay de red)
try {
    foreach ($oldRun in @("ACAAdvisorAgent", "ACAAdvisorLiveStream", "ACAAdvisorDLP")) {
        Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $oldRun -ErrorAction SilentlyContinue
        cmd.exe /c "schtasks /delete /tn `"$oldRun`" /f 2>nul" | Out-Null
    }

    $launcherCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherScriptPath`""
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ACAAdvisorLauncher" -Value $launcherCmd -Force

    # Tarea programada XML con Delay=15s, WorkingDirectory explicito, soporte bateria y sin limite de 72h
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>ACA Advisor Corporate Agent Launcher and Watchdog v3.0.5</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT15S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$launcherScriptPath"</Arguments>
      <WorkingDirectory>$mainDir</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
    $xmlPath = Join-Path $env:TEMP "ACAAdvisorLauncher_task.xml"
    [System.IO.File]::WriteAllText($xmlPath, $taskXml, [System.Text.Encoding]::Unicode)
    cmd.exe /c "schtasks /create /tn `"ACAAdvisorLauncher`" /xml `"$xmlPath`" /f 2>nul" | Out-Null
    Remove-Item -Path $xmlPath -Force -ErrorAction SilentlyContinue
    Write-Host "  [+] Autoarranque unificado configurado (ACAAdvisorLauncher con WorkingDirectory y delay de red)." -ForegroundColor Green
} catch {
    Write-Host "  [!] Advertencia configurando autoarranque: $_" -ForegroundColor Yellow
}

# Refrescar cache de iconos de Windows Explorer para que el nuevo .ico sea visible de inmediato
try { Start-Process "ie4uinit.exe" -ArgumentList "-show" -WindowStyle Hidden -ErrorAction SilentlyContinue } catch {}

# 9. Iniciar Launcher Watchdog (que inicia aca-agent.exe con token fresco + Live Stream + DLP)
Write-Host "`n[5/6] Iniciando Launcher Watchdog, agente principal, pantalla en vivo y monitor DLP..." -ForegroundColor Yellow
if (Test-Path $launcherScriptPath) {
    Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherScriptPath`"" -WorkingDirectory $mainDir -WindowStyle Hidden
} else {
    Start-Process $exePath -WorkingDirectory $mainDir
    if (Test-Path $streamScriptPath) {
        Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$streamScriptPath`"" -WorkingDirectory $mainDir -WindowStyle Hidden
    }
    if (Test-Path $dlpScriptPath) {
        Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$dlpScriptPath`"" -WorkingDirectory $mainDir -WindowStyle Hidden
    }
}
Start-Sleep -Seconds 6

$p = Get-Process -Name "aca-agent","empmonitor" -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "  [OK] Agente principal activo (PID: $($p.Id -join ', '))." -ForegroundColor Green
    $p | Select-Object Id, ProcessName, @{Name="RAM (MB)";Expression={[math]::Round($_.WS/1MB,2)}} | Format-Table -AutoSize
} else {
    Write-Host "  [!] El agente principal aun esta inicializando (ver logs\launcherLog.txt)." -ForegroundColor Yellow
}

$sp = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*live-stream.ps1*' }
if ($sp) {
    Write-Host "  [OK] Modulo de transmision de pantalla en vivo activo (PID: $($sp.ProcessId -join ', '))." -ForegroundColor Green
} else {
    Write-Host "  [!] El modulo de pantalla en vivo no inicio. Verifique logs\streamLog.txt." -ForegroundColor Yellow
}

# 10. Comprobar registros de actividad y conectividad
Write-Host "`n[6/6] Comprobando transmision y conectividad..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

$launcherLogPath = Join-Path (Join-Path $mainDir "logs") "launcherLog.txt"
if (Test-Path $launcherLogPath) {
    Write-Host "`n--- Estado del Launcher Watchdog (logs\launcherLog.txt) ---" -ForegroundColor Cyan
    Get-Content $launcherLogPath -Tail 5 -ErrorAction SilentlyContinue | Write-Host -ForegroundColor Gray
}
$streamLogPath = Join-Path (Join-Path $mainDir "logs") "streamLog.txt"
if (Test-Path $streamLogPath) {
    Write-Host "`n--- Estado del modulo Live Stream (logs\streamLog.txt) ---" -ForegroundColor Cyan
    Get-Content $streamLogPath -Tail 5 -ErrorAction SilentlyContinue | Write-Host -ForegroundColor Gray
}

try {
    if ($UseHttps) {
        $t = Test-NetConnection -ComputerName $ServerHost -Port 443 -WarningAction SilentlyContinue
        if ($t.TcpTestSucceeded) {
            Write-Host "`n  [+] Comunicacion HTTPS confirmada en puerto 443 ($ServerHost)!" -ForegroundColor Green
        } else {
            Write-Host "`n  [!] Advertencia: Puerto 443 no respondio en $ServerHost." -ForegroundColor Yellow
        }
    } else {
        $t1 = Test-NetConnection -ComputerName $ServerHost -Port 3004 -WarningAction SilentlyContinue
        $t2 = Test-NetConnection -ComputerName $ServerHost -Port 3001 -WarningAction SilentlyContinue
        $t3 = Test-NetConnection -ComputerName $ServerHost -Port 3003 -WarningAction SilentlyContinue
        if ($t1.TcpTestSucceeded -and $t2.TcpTestSucceeded -and $t3.TcpTestSucceeded) {
            Write-Host "`n  [+] Comunicacion confirmada en puertos 3004 (Desktop), 3001 (Logs) y 3003 (Realtime)!" -ForegroundColor Green
        } else {
            Write-Host "`n  [!] Advertencia: Algun puerto no respondio al test TCP local." -ForegroundColor Yellow
        }
    }
} catch {}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "      CONFIGURACION v3.0.6 APLICADA EXITOSAMENTE          " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
if ($AgentEmail) {
    Write-Host "Equipo vinculado como: $AgentEmail (MachineID: $activeMac)"
} else {
    Write-Host "Modo Visible activo: inicie sesion en la ventana de ACA Advisor Agent."
}
Write-Host "Verifique el panel web en: $PanelUrl"
