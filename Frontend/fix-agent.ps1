# ==============================================================================
# ACA ADVISOR S.A.S. - CONFIGURACION INTEGRAL DEL AGENTE CORPORATIVO WINDOWS
# ==============================================================================
# Configura el binario nativo (aca-agent.exe o empmonitor.exe), aplica credenciales
# corporativas y politicas de monitoreo en tiempo real, registra exclusiones en
# Windows Defender y vincula el equipo al servidor central ACA ADVISOR.
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ACA Advisor Agent - Configurador Oficial"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      ACA ADVISOR S.A.S. - AGENTE CORPORATIVO WINDOWS     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ServerHost = "192.168.0.155"
$OrgId = "OjUpRAB"
$AgentEmail = "F8:89:D2:F5:4A:87_@Yolaine.OjUpRAB"
$AgentCryptoPassword = "43d7dbcf81bad521552d1b59e619cced:ede717306619e874100560153a96ecc3"

# 1. Comprobacion y elevacion de permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Solicitando permisos de Administrador..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        } else {
            Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"& { irm http://$ServerHost:8081/downloads/fix-agent.ps1 | iex }`"" -Verb RunAs
        }
        exit
    } catch {
        Write-Host "[-] Se requieren permisos de Administrador para configurar el agente." -ForegroundColor Red
        exit 1
    }
}

# 2. Agregar exclusiones oficiales en Windows Defender (Antivirus)
Write-Host "`n[1/6] Configurando exclusiones en Windows Defender..." -ForegroundColor Yellow
$CandidateDirs = @(
    "C:\Program Files\ACA Advisor Agent",
    "C:\Program Files (x86)\ACA Advisor Agent",
    "C:\Program Files\Empmonitor",
    "C:\Program Files (x86)\Empmonitor",
    "C:\Program Files\EmpMonitor\EmpMonitor"
)

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

# 3. Cerrar instancias previas
Write-Host "`n[2/6] Cerrando instancias anteriores del agente..." -ForegroundColor Yellow
Stop-Process -Name "aca-agent","empmonitor" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Localizar carpetas activas de instalacion
$activeDirs = @()
foreach ($dir in $CandidateDirs) {
    if ((Test-Path "$dir\aca-agent.exe") -or (Test-Path "$dir\empmonitor.exe")) {
        $activeDirs += $dir
    }
}

# Si no existe ninguna, descargar e instalar
if ($activeDirs.Count -eq 0) {
    $primaryDir = "C:\Program Files\ACA Advisor Agent"
    Write-Host "[*] No se detecto instalacion previa. Descargando ACA_Advisor_Agent_Setup.exe..." -ForegroundColor Cyan
    $installerPath = "$env:TEMP\ACA_Advisor_Agent_Setup.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "http://$ServerHost:8081/downloads/ACA_Advisor_Agent_Setup.exe" -OutFile $installerPath -UseBasicParsing
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

# 4. Configurar cada directorio encontrado (Permisos, Config, Plugins Qt)
Write-Host "`n[3/6] Configurando archivos de conexion en directorios del agente..." -ForegroundColor Yellow
$configJson = @"
{
  "id": "$OrgId",
  "mode": "office",
  "api": "http://$ServerHost:3001/api/v1",
  "login": "http://$ServerHost:3004/api/v3",
  "pipeline": "http://$ServerHost:3001/api/v1",
  "realtime": "ws://$ServerHost:3003",
  "updates": "http://$ServerHost:3004/api/v3"
}
"@

$lockFiles = @("planExpiryFile.txt", "EmployeeTimestamp.txt", "dataLog.txt", "usbInsLogs.txt", "usbRemLogs.txt")

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
    cmd.exe /c "attrib -r `"$configFile1`" 2>nul & attrib -r `"$configFile2`" 2>nul"

    [System.IO.File]::WriteAllText($configFile1, $configJson, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($configFile2, $configJson, [System.Text.Encoding]::UTF8)
    cmd.exe /c "attrib +r `"$configFile1`" & attrib +r `"$configFile2`""
    Write-Host "    [+] config.js y config.json aplicados." -ForegroundColor Green

    # Asegurar plugins de plataforma Qt
    $qtConfPath = Join-Path $targetDir "qt.conf"
    "[Paths]`r`nPrefix=.`r`nPlugins=plugins" | Out-File -FilePath $qtConfPath -Encoding ascii -Force
    $pluginsPlatforms = Join-Path $targetDir "plugins\platforms"
    $directPlatforms = Join-Path $targetDir "platforms"
    if ((Test-Path $pluginsPlatforms) -and -not (Test-Path $directPlatforms)) {
        Copy-Item -Path $pluginsPlatforms -Destination $directPlatforms -Recurse -Force
    }
}

# 5. Configurar el Registro de Windows (QSettings de Qt: screen\empm y Empmonitor)
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
        Set-ItemProperty -Path $root -Name "backend_base" -Value "http://$ServerHost:3001/api/v1" -Force
        Set-ItemProperty -Path $root -Name "backend_base_login" -Value "http://$ServerHost:3004/api/v3" -Force
        Set-ItemProperty -Path $root -Name "update_base_url" -Value "http://$ServerHost:3004/api/v3" -Force
        Set-ItemProperty -Path $root -Name "organization_id" -Value "$OrgId" -Force

        # Credenciales de autenticacion local directa
        $authPath = "$root\auth"
        if (-not (Test-Path $authPath)) { New-Item -Path $authPath -Force | Out-Null }
        Set-ItemProperty -Path $authPath -Name "email" -Value $AgentEmail -Force
        Set-ItemProperty -Path $authPath -Name "crypto_password" -Value $AgentCryptoPassword -Force

        # Politicas remotas y frecuencias de envio
        $fromRemote = "$root\appSettings\from_remote"
        if (-not (Test-Path $fromRemote)) { New-Item -Path $fromRemote -Force | Out-Null }
        Set-ItemProperty -Path $fromRemote -Name "account_type" -Value "office" -Force
        Set-ItemProperty -Path $fromRemote -Name "screenshotPeriodSec" -Value 20 -Type DWord -Force
        Set-ItemProperty -Path $fromRemote -Name "ADUserInfoSendPerSec" -Value 60 -Type DWord -Force

        $appSettings = "$root\appSettings"
        if (-not (Test-Path $appSettings)) { New-Item -Path $appSettings -Force | Out-Null }
        Set-ItemProperty -Path $appSettings -Name "screenshotQuality" -Value 50 -Type DWord -Force
        Set-ItemProperty -Path $appSettings -Name "dataSendingPeriodSec" -Value 30 -Type DWord -Force
        Set-ItemProperty -Path $appSettings -Name "mode" -Value "office" -Force

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
    } catch {}
}
Write-Host "  [+] Registro configurado con endpoints, credenciales y frecuencias optimas." -ForegroundColor Green

# 6. Configurar autoarranque
$mainDir = $activeDirs[0]
$exePath = Join-Path $mainDir "aca-agent.exe"
if (-not (Test-Path $exePath)) { $exePath = Join-Path $mainDir "empmonitor.exe" }

try {
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ACAAdvisorAgent" -Value "`"$exePath`"" -Force
    cmd.exe /c "schtasks /create /tn `"ACAAdvisorAgent`" /tr `"\`"$exePath\`"`" /sc onlogon /rl highest /f 2>nul"
    Write-Host "  [+] Tarea programada y clave Run configuradas." -ForegroundColor Green
} catch {}

# 7. Iniciar el agente en la sesion interactiva
Write-Host "`n[5/6] Iniciando el agente en sesion de usuario..." -ForegroundColor Yellow
Start-Process $exePath -WorkingDirectory $mainDir
Start-Sleep -Seconds 4

$p = Get-Process -Name "aca-agent","empmonitor" -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "  [OK] Proceso activo (PID: $($p.Id -join ', '))." -ForegroundColor Green
    $p | Select-Object Id, ProcessName, @{Name="RAM (MB)";Expression={[math]::Round($_.WS/1MB,2)}} | Format-Table -AutoSize
} else {
    Write-Host "  [!] El proceso no quedo activo. Verifique dependencias de Qt." -ForegroundColor Yellow
}

# 8. Comprobar registros de actividad y conectividad
Write-Host "`n[6/6] Verificando conectividad con servidor central ($ServerHost)..." -ForegroundColor Yellow
$logPath = Join-Path $mainDir "dataLog.txt"
if (Test-Path $logPath) {
    Write-Host "`n--- Ultimas lineas de dataLog.txt ---" -ForegroundColor Cyan
    Get-Content $logPath -Tail 10 -ErrorAction SilentlyContinue | Write-Host -ForegroundColor Gray
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
Write-Host "Equipo vinculado como: $AgentEmail"
Write-Host "Verifique el panel web en: http://$ServerHost:8081/admin/live-monitoring"
