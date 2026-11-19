# ==============================================================================
# ACA ADVISOR S.A.S. - CONFIGURACION INTEGRAL DEL AGENTE CORPORATIVO WINDOWS
# Soporta modo Sigilo ("office") y modo Visible ("personal")
# ==============================================================================
param(
    [string]$ServerHost = "192.168.0.155",
    [string]$OrgId = "OjUpRAB",
    [ValidateSet("office", "personal")]
    [string]$Mode = "office"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ACA Advisor Agent - Configurador Oficial ($Mode)"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      ACA ADVISOR S.A.S. - AGENTE CORPORATIVO WINDOWS     " -ForegroundColor Cyan
Write-Host "                   Modo: $Mode                            " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$AgentCryptoPassword = "43d7dbcf81bad521552d1b59e619cced:ede717306619e874100560153a96ecc3"
$AgentEmail = ""

# 1. Comprobacion y elevacion de permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Solicitando permisos de Administrador..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ServerHost `"$ServerHost`" -OrgId `"$OrgId`" -Mode `"$Mode`"" -Verb RunAs
        } else {
            Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"& { irm http://${ServerHost}:8081/downloads/fix-agent.ps1 | iex }`"" -Verb RunAs
        }
        exit
    } catch {
        Write-Host "[-] Se requieren permisos de Administrador para configurar el agente." -ForegroundColor Red
        exit 1
    }
}

# 2. Deteccion de identidad de la maquina
$computerName = $env:COMPUTERNAME
$systemUser = $env:USERNAME
if (-not $systemUser -or $systemUser -eq "SYSTEM") {
    $systemUser = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
    if ($systemUser -and $systemUser.Contains('\')) {
        $systemUser = $systemUser.Split('\')[1]
    }
}
if (-not $systemUser) { $systemUser = "Usuario" }

# Usar MachineGuid de Windows (el mismo identificador que usa aca-agent.exe) para evitar usuarios duplicados
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
Write-Host "    - MAC:        $activeMac" -ForegroundColor White
Write-Host "    - Modo:       $Mode" -ForegroundColor White

# 3. Auto-registro dinamico en servidor ACA ADVISOR (solo modo sigilo / office)
if ($Mode -eq "office") {
    $AgentEmail = "$($activeMac)_@$($systemUser).$OrgId"
    Write-Host "`n[*] Registrando maquina en servidor central ($ServerHost)..." -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $regPayload = @{
            macId = $activeMac
            organizationId = $OrgId
            username = $systemUser
            computerName = $computerName
            firstname = "$computerName -"
            lastname = $systemUser
        } | ConvertTo-Json

        $regRes = Invoke-RestMethod -Uri "http://${ServerHost}:3004/api/v3/auth/register" -Method Post -Body $regPayload -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop
        if ($regRes -and $regRes.code -eq 200) {
            if ($regRes.data -and $regRes.data.email) {
                $AgentEmail = $regRes.data.email
            } elseif ($regRes.email) {
                $AgentEmail = $regRes.email
            }
            if ($regRes.data -and $regRes.data.crypto_password) {
                $AgentCryptoPassword = $regRes.data.crypto_password
            }
            Write-Host "  [+] Registro exitoso en servidor: $AgentEmail" -ForegroundColor Green
        } else {
            Write-Host "  [!] El servidor respondio: $($regRes | ConvertTo-Json -Compress)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [!] Nota sobre registro: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[*] Modo visible (personal): el empleado iniciara sesion desde la interfaz del agente." -ForegroundColor Cyan
    try {
        if (Test-Path "HKCU:\Software\screen\empm\auth") {
            $existingAuth = Get-ItemProperty -Path "HKCU:\Software\screen\empm\auth" -ErrorAction SilentlyContinue
            if ($existingAuth.email) { $AgentEmail = [string]$existingAuth.email }
            if ($existingAuth.crypto_password) { $AgentCryptoPassword = [string]$existingAuth.crypto_password }
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

# 5. Cerrar instancias previas
Write-Host "`n[2/6] Cerrando instancias anteriores del agente..." -ForegroundColor Yellow
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
        Invoke-WebRequest -Uri "http://${ServerHost}:8081/downloads/$installerName" -OutFile $installerPath -UseBasicParsing
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

# 6. Configurar cada directorio encontrado (Permisos, Config, Plugins Qt)
Write-Host "`n[3/6] Configurando archivos de conexion en directorios del agente..." -ForegroundColor Yellow
$configJson = @"
{
  "id": "$OrgId",
  "mode": "$Mode",
  "api": "http://${ServerHost}:3001/api/v1",
  "login": "http://${ServerHost}:3004/api/v3",
  "pipeline": "http://${ServerHost}:3001/api/v1",
  "realtime": "ws://${ServerHost}:3003",
  "updates": "http://${ServerHost}:3004/api/v3"
}
"@

$lockFiles = @("planExpiryFile.txt", "EmployeeTimestamp.txt", "dataLog.txt", "usbInsLogs.txt", "usbRemLogs.txt", "local_db20.db", "local_db20.db-journal", "temp_db20.db", "temp_db20.db-journal")

foreach ($targetDir in $activeDirs) {
    Write-Host "  [*] Procesando: $targetDir" -ForegroundColor Cyan

    # Permisos de escritura para usuarios (requerido por SQLite y logs locales)
    cmd.exe /c "icacls `"$targetDir`" /grant Users:(OI)(CI)F /T /C /Q 2>nul"
    $failedSsDir = Join-Path $targetDir "failed_screenshots"
    if (-not (Test-Path $failedSsDir)) { New-Item -ItemType Directory -Path $failedSsDir -Force | Out-Null }
    cmd.exe /c "icacls `"$failedSsDir`" /grant Users:(OI)(CI)F /T /C /Q 2>nul"

    # Limpiar archivos de bloqueo residuales
    foreach ($lf in $lockFiles) {
        $fPath = Join-Path $targetDir $lf
        if (Test-Path $fPath) {
            Remove-Item -Path $fPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Escribir config.js y config.json
    $configsFolder = Join-Path $targetDir "configs"
    if (-not (Test-Path $configsFolder)) { New-Item -ItemType Directory -Path $configsFolder -Force | Out-Null }
    cmd.exe /c "icacls `"$configsFolder`" /grant Users:(OI)(CI)F /T /C /Q 2>nul"

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

# 7. Configurar el Registro de Windows (QSettings de Qt: screen\empm y Empmonitor)
Write-Host "`n[4/6] Configurando Registro de Windows (QSettings y credenciales)..." -ForegroundColor Yellow

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

        # Parametros principales del motor C++/Qt
        Set-ItemProperty -Path $root -Name "api" -Value "http://${ServerHost}:3001/api/v1" -Force
        Set-ItemProperty -Path $root -Name "pipeline" -Value "http://${ServerHost}:3001/api/v1" -Force
        Set-ItemProperty -Path $root -Name "realtime" -Value "ws://${ServerHost}:3003" -Force
        Set-ItemProperty -Path $root -Name "login" -Value "http://${ServerHost}:3004/api/v3" -Force
        Set-ItemProperty -Path $root -Name "updates" -Value "http://${ServerHost}:3004/api/v3" -Force
        Set-ItemProperty -Path $root -Name "backend_base" -Value "http://${ServerHost}:3001/api/v1" -Force
        Set-ItemProperty -Path $root -Name "backend_base_login" -Value "http://${ServerHost}:3004/api/v3" -Force
        Set-ItemProperty -Path $root -Name "update_base_url" -Value "http://${ServerHost}:3004/api/v3" -Force
        Set-ItemProperty -Path $root -Name "organization_id" -Value "$OrgId" -Force
        Set-ItemProperty -Path $root -Name "identifier" -Value "$OrgId" -Force

        # Credenciales de autenticacion local directa (solo sobrescribir en modo sigilo / office)
        if ($Mode -eq "office" -and $AgentEmail) {
            $authPath = "$root\auth"
            if (-not (Test-Path $authPath)) { New-Item -Path $authPath -Force | Out-Null }
            Set-ItemProperty -Path $authPath -Name "email" -Value $AgentEmail -Force
            Set-ItemProperty -Path $authPath -Name "crypto_password" -Value $AgentCryptoPassword -Force
        }

        # Politicas remotas y frecuencias de envio
        $fromRemote = "$root\appSettings\from_remote"
        if (-not (Test-Path $fromRemote)) { New-Item -Path $fromRemote -Force | Out-Null }
        Set-ItemProperty -Path $fromRemote -Name "account_type" -Value "$Mode" -Force
        Set-ItemProperty -Path $fromRemote -Name "screenshotPeriodSec" -Value 20 -Type DWord -Force
        Set-ItemProperty -Path $fromRemote -Name "ADUserInfoSendPerSec" -Value 60 -Type DWord -Force

        $appSettings = "$root\appSettings"
        if (-not (Test-Path $appSettings)) { New-Item -Path $appSettings -Force | Out-Null }
        Set-ItemProperty -Path $appSettings -Name "screenshotQuality" -Value 50 -Type DWord -Force
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
Write-Host "  [+] Registro configurado con endpoints, modo ($Mode) y frecuencias optimas." -ForegroundColor Green

# 8. Configurar Modulo de Transmision de Pantalla en Tiempo Real (empaquetado localmente o descargado)
$mainDir = $activeDirs[0]
$exePath = Join-Path $mainDir "aca-agent.exe"
if (-not (Test-Path $exePath)) { $exePath = Join-Path $mainDir "empmonitor.exe" }

# Detener instancias previas del streamer de pantalla y monitor DLP
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*live-stream.ps1*' -or $_.CommandLine -like '*dlp-monitor.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {}

$streamScriptPath = Join-Path $mainDir "live-stream.ps1"
$dlpScriptPath    = Join-Path $mainDir "dlp-monitor.ps1"
$streamConfigPath = Join-Path (Join-Path $mainDir "configs") "stream.json"

# Si no existen localmente (instalacion antigua), descargarlos del servidor
if (-not (Test-Path $streamScriptPath)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "http://${ServerHost}:8081/downloads/live-stream.ps1?v=11" -OutFile $streamScriptPath -UseBasicParsing -ErrorAction Stop
        Write-Host "  [+] Modulo Live Screen descargado desde servidor." -ForegroundColor Green
    } catch {
        Write-Host "  [!] No se pudo descargar live-stream.ps1: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [+] Modulo Live Screen detectado localmente en $streamScriptPath." -ForegroundColor Green
}

if (-not (Test-Path $dlpScriptPath)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "http://${ServerHost}:8081/downloads/dlp-monitor.ps1?v=1" -OutFile $dlpScriptPath -UseBasicParsing -ErrorAction Stop
        Write-Host "  [+] Modulo DLP & Capturas descargado desde servidor." -ForegroundColor Green
    } catch {
        Write-Host "  [!] No se pudo descargar dlp-monitor.ps1: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [+] Modulo DLP & Capturas detectado localmente en $dlpScriptPath." -ForegroundColor Green
}

try {
    $streamCfg = @{
        server   = $ServerHost
        mode     = $Mode
        email    = $AgentEmail
        password = if ($AgentEmail) { $AgentCryptoPassword } else { "" }
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($streamConfigPath, $streamCfg, [System.Text.Encoding]::UTF8)
    Write-Host "  [+] Configuracion stream.json generada." -ForegroundColor Green
} catch {
    Write-Host "  [!] Error escribiendo stream.json: $_" -ForegroundColor Yellow
}

# Configurar autoarranque (Agente + Live Screen Streamer + Monitor DLP)
try {
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ACAAdvisorAgent" -Value "`"$exePath`"" -Force
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ACAAdvisorLiveStream" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$streamScriptPath`"" -Force
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ACAAdvisorDLP" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$dlpScriptPath`"" -Force
    cmd.exe /c "schtasks /create /tn `"ACAAdvisorAgent`" /tr `"\`"$exePath\`"`" /sc onlogon /rl highest /f 2>nul"
    cmd.exe /c "schtasks /create /tn `"ACAAdvisorLiveStream`" /tr `"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \`"$streamScriptPath\`"`" /sc onlogon /rl highest /f 2>nul"
    cmd.exe /c "schtasks /create /tn `"ACAAdvisorDLP`" /tr `"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \`"$dlpScriptPath\`"`" /sc onlogon /rl highest /f 2>nul"
    Write-Host "  [+] Tareas programadas y claves Run configuradas (Agente, Live Stream y DLP)." -ForegroundColor Green
} catch {}

# 9. Iniciar el agente, modulo Live Stream y modulo DLP en la sesion interactiva
Write-Host "`n[5/6] Iniciando el agente, pantalla en vivo y monitor DLP..." -ForegroundColor Yellow
Start-Process $exePath -WorkingDirectory $mainDir
if (Test-Path $streamScriptPath) {
    Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$streamScriptPath`"" -WorkingDirectory $mainDir -WindowStyle Hidden
}
if (Test-Path $dlpScriptPath) {
    Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$dlpScriptPath`"" -WorkingDirectory $mainDir -WindowStyle Hidden
}
Start-Sleep -Seconds 4

$p = Get-Process -Name "aca-agent","empmonitor" -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "  [OK] Agente principal activo (PID: $($p.Id -join ', '))." -ForegroundColor Green
    $p | Select-Object Id, ProcessName, @{Name="RAM (MB)";Expression={[math]::Round($_.WS/1MB,2)}} | Format-Table -AutoSize
} else {
    Write-Host "  [!] El proceso principal no quedo activo. Verifique dependencias de Qt." -ForegroundColor Yellow
}

$sp = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*live-stream.ps1*' }
if ($sp) {
    Write-Host "  [OK] Modulo de transmision de pantalla en vivo activo (PID: $($sp.ProcessId -join ', '))." -ForegroundColor Green
} else {
    Write-Host "  [!] El modulo de pantalla en vivo no inicio. Verifique permisos." -ForegroundColor Yellow
}

# 10. Comprobar registros de actividad y conectividad
Write-Host "`n[6/6] Esperando inicializacion y comprobando transmision..." -ForegroundColor Yellow
Start-Sleep -Seconds 4

$streamLogPath = Join-Path $mainDir "streamLog.txt"
if (Test-Path $streamLogPath) {
    Write-Host "`n--- Estado del modulo Live Stream (streamLog.txt) ---" -ForegroundColor Cyan
    Get-Content $streamLogPath -Tail 5 -ErrorAction SilentlyContinue | Write-Host -ForegroundColor Gray
}

try {
    $t1 = Test-NetConnection -ComputerName $ServerHost -Port 3004 -WarningAction SilentlyContinue
    $t2 = Test-NetConnection -ComputerName $ServerHost -Port 3001 -WarningAction SilentlyContinue
    $t3 = Test-NetConnection -ComputerName $ServerHost -Port 3003 -WarningAction SilentlyContinue
    if ($t1.TcpTestSucceeded -and $t2.TcpTestSucceeded -and $t3.TcpTestSucceeded) {
        Write-Host "`n  [+] Comunicacion confirmada en puertos 3004 (Desktop), 3001 (Logs) y 3003 (Realtime)!" -ForegroundColor Green
    } else {
        Write-Host "`n  [!] Advertencia: Algun puerto no respondio al test TCP local." -ForegroundColor Yellow
    }
} catch {}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "       CONFIGURACION APLICADA EXITOSAMENTE               " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
if ($AgentEmail) {
    Write-Host "Equipo vinculado como: $AgentEmail"
} else {
    Write-Host "Modo Visible activo: inicie sesion en la ventana de ACA Advisor Agent."
}
Write-Host "Verifique el panel web en: http://${ServerHost}:8081/admin/live-monitoring"
