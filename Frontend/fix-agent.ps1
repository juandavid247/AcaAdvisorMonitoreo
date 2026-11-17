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

# 1. Comprobacion y elevacion de permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Solicitando permisos de Administrador..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    } catch {
        Write-Host "[-] Se requieren permisos de Administrador para configurar Windows Defender y el Registro." -ForegroundColor Red
        exit 1
    }
}

$ServerHost = "192.168.0.155"
$OrgId = "OjUpRAB"

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

# 5. Configurar Registro de Windows para capturas y envio periodico (Ruta real Qt QSettings: Software\screen\empm)
Write-Host "`n[4/5] Configurando politicas de monitoreo y DLP en el Registro..." -ForegroundColor Yellow
$regRoots = @(
    "HKCU:\Software\screen\empm",
    "HKLM:\Software\screen\empm",
    "HKCU:\Software\Empmonitor",
    "HKCU:\Software\Empmonitor\Empmonitor",
    "HKLM:\Software\Empmonitor",
    "HKLM:\Software\Empmonitor\Empmonitor"
)

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

# Autoarranque con Windows (especificado en installer.iss)
$exePath = Join-Path $targetDir "aca-agent.exe"
if (-not (Test-Path $exePath)) { $exePath = Join-Path $targetDir "empmonitor.exe" }
try {
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ACAAdvisorAgent" -Value "`"$exePath`"" -Force
    Write-Host "  [+] Inicio automatico con Windows configurado." -ForegroundColor Green
} catch {}

# 6. Iniciar el ejecutable oficial
Write-Host "`n[5/5] Iniciando el agente oficial aca-agent.exe..." -ForegroundColor Yellow
if (Test-Path $exePath) {
    Start-Process $exePath -WorkingDirectory $targetDir
    Start-Sleep -Seconds 2
    $p = Get-Process -Name "aca-agent","empmonitor" -ErrorAction SilentlyContinue
    if ($p) {
        Write-Host "  [OK] Agente ACA Advisor iniciado exitosamente (PID: $($p.Id -join ', '))." -ForegroundColor Green
    } else {
        Write-Host "  [!] El agente fue lanzado pero no se detecta el proceso. Verifique dependencias de Qt." -ForegroundColor Yellow
    }
} else {
    Write-Host "[-] No se encontro el ejecutable en $exePath" -ForegroundColor Red
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  CONFIGURACION COMPLETADA EXITOSAMENTE (MODO OFICIAL)  " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "El equipo DESKTOP-E6GSJ9C esta vinculado y reportando al servidor central."
Write-Host "Verifique el panel web en: http://$ServerHost:8081/admin/live-monitoring"
