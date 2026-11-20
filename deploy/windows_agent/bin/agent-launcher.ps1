# ==============================================================================
# ACA ADVISOR S.A.S. - Launcher & Watchdog Corporativo v3.0.6
# Garantiza red/servidor disponible, token fresco en HKCU, WorkingDirectory
# correcto y auto-recuperacion continua tras apagado/reinicio del equipo.
# ==============================================================================
param()

$ErrorActionPreference = "SilentlyContinue"

# Evitar instancias duplicadas en la misma sesion interactiva
$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\ACAAdvisorLauncher", [ref]$mutexCreated)
if (-not $mutexCreated) { exit 0 }

$BaseDir    = $PSScriptRoot
$ConfigPath = Join-Path $BaseDir "configs\stream.json"
$LogDir     = Join-Path $BaseDir "logs"
if (-not (Test-Path $LogDir)) { try { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null } catch {} }
$LogFile    = if (Test-Path $LogDir) { Join-Path $LogDir "launcherLog.txt" } else { Join-Path $env:TEMP "aca_launcherLog.txt" }
$MaxLogBytes = 5MB

$ExePath    = Join-Path $BaseDir "aca-agent.exe"
if (-not (Test-Path $ExePath)) { $ExePath = Join-Path $BaseDir "empmonitor.exe" }
$StreamPath = Join-Path $BaseDir "live-stream.ps1"
$DlpPath    = Join-Path $BaseDir "dlp-monitor.ps1"

function Write-LauncherLog($msg) {
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

function Get-LauncherConfig {
    $cfg = @{
        server       = "192.168.0.155"
        orgId        = "OjUpRAB"
        mode         = "office"
        useHttps     = $false
        apiUrl       = ""
        loginUrl     = ""
        realtimeUrl  = ""
        email        = ""
        password     = ""
        deviceId     = (Get-MachineDeviceId)
        computerName = $env:COMPUTERNAME
    }

    if (Test-Path $ConfigPath) {
        try {
            $j = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            if ($j.server)      { $cfg.server      = [string]$j.server }
            if ($j.orgId)       { $cfg.orgId       = [string]$j.orgId }
            if ($j.mode)        { $cfg.mode        = [string]$j.mode }
            if ($null -ne $j.useHttps) { $cfg.useHttps = [bool]$j.useHttps }
            if ($j.apiUrl)      { $cfg.apiUrl      = [string]$j.apiUrl }
            if ($j.loginUrl)    { $cfg.loginUrl    = [string]$j.loginUrl }
            if ($j.realtimeUrl) { $cfg.realtimeUrl = [string]$j.realtimeUrl }
            if ($j.email)       { $cfg.email       = [string]$j.email }
            if ($j.password)    { $cfg.password    = [string]$j.password }
            if ($j.deviceId -and -not $cfg.deviceId) { $cfg.deviceId = [string]$j.deviceId }
        } catch {}
    }

    # Leer respaldo de config.json si falta algo
    $agentCfgPath = Join-Path $BaseDir "configs\config.json"
    if (Test-Path $agentCfgPath) {
        try {
            $ac = Get-Content -Path $agentCfgPath -Raw | ConvertFrom-Json
            if ($ac.id -and -not $cfg.orgId) { $cfg.orgId = [string]$ac.id }
            if ($ac.mode -and -not $cfg.mode) { $cfg.mode = [string]$ac.mode }
            if ($ac.api -and -not $cfg.apiUrl) { $cfg.apiUrl = [string]$ac.api }
            if ($ac.login -and -not $cfg.loginUrl) { $cfg.loginUrl = "$([string]$ac.login)/employee/login" }
            if ($ac.realtime -and -not $cfg.realtimeUrl) { $cfg.realtimeUrl = [string]$ac.realtime }
        } catch {}
    }

    foreach ($ap in @("HKCU:\Software\screen\empm\auth", "HKLM:\Software\screen\empm\auth")) {
        try {
            if (Test-Path $ap) {
                $props = Get-ItemProperty -Path $ap -ErrorAction SilentlyContinue
                if ($props.email -and ($cfg.mode -eq "personal" -or -not $cfg.email)) { $cfg.email = [string]$props.email }
                if ($props.crypto_password -and ($cfg.mode -eq "personal" -or -not $cfg.password)) { $cfg.password = [string]$props.crypto_password }
            }
        } catch {}
    }

    $srv = $cfg.server.Trim()
    if (-not $cfg.apiUrl) {
        $cfg.apiUrl = if ($cfg.useHttps) { "https://${srv}/logs/api/v1" } else { "http://${srv}:3001/api/v1" }
    }
    if (-not $cfg.loginUrl) {
        $cfg.loginUrl = if ($cfg.useHttps) { "https://${srv}/desktop/api/v3/employee/login" } else { "http://${srv}:3004/api/v3/employee/login" }
    }
    if (-not $cfg.realtimeUrl) {
        $cfg.realtimeUrl = if ($cfg.useHttps) { "wss://${srv}/ws/realtime" } else { "ws://${srv}:3003" }
    }
    $cfg.loginBase = $cfg.loginUrl -replace '/employee/login$', ''
    return $cfg
}

function Sync-UserRegistry($cfg, $email, $cryptoPass, $accessToken, $identifier) {
    $regRoots = @(
        "HKCU:\Software\screen\empm",
        "HKCU:\Software\Empmonitor",
        "HKCU:\Software\EmpMonitor\EmpMonitor"
    )
    foreach ($root in $regRoots) {
        try {
            if (-not (Test-Path $root)) { New-Item -Path $root -Force | Out-Null }
            Set-ItemProperty -Path $root -Name "api" -Value $cfg.apiUrl -Force
            Set-ItemProperty -Path $root -Name "pipeline" -Value $cfg.apiUrl -Force
            Set-ItemProperty -Path $root -Name "realtime" -Value $cfg.realtimeUrl -Force
            Set-ItemProperty -Path $root -Name "login" -Value $cfg.loginBase -Force
            Set-ItemProperty -Path $root -Name "updates" -Value $cfg.loginBase -Force
            Set-ItemProperty -Path $root -Name "backend_base" -Value $cfg.apiUrl -Force
            Set-ItemProperty -Path $root -Name "backend_base_login" -Value $cfg.loginBase -Force
            Set-ItemProperty -Path $root -Name "update_base_url" -Value $cfg.loginBase -Force
            Set-ItemProperty -Path $root -Name "organization_id" -Value $cfg.orgId -Force
            Set-ItemProperty -Path $root -Name "identifier" -Value $(if ($identifier) { $identifier } else { $cfg.orgId }) -Force

            $appSettings = "$root\appSettings"
            if (-not (Test-Path $appSettings)) { New-Item -Path $appSettings -Force | Out-Null }
            Set-ItemProperty -Path $appSettings -Name "mode" -Value $cfg.mode -Force
            Set-ItemProperty -Path $appSettings -Name "dataSendingPeriodSec" -Value 30 -Type DWord -Force
            Set-ItemProperty -Path $appSettings -Name "screenshotQuality" -Value 82 -Type DWord -Force

            $fromRemote = "$root\appSettings\from_remote"
            if (-not (Test-Path $fromRemote)) { New-Item -Path $fromRemote -Force | Out-Null }
            Set-ItemProperty -Path $fromRemote -Name "account_type" -Value $cfg.mode -Force
            Set-ItemProperty -Path $fromRemote -Name "screenshotPeriodSec" -Value 20 -Type DWord -Force
            Set-ItemProperty -Path $fromRemote -Name "ADUserInfoSendPerSec" -Value 60 -Type DWord -Force

            $dataKey = "$root\appSettings\data"
            if (-not (Test-Path $dataKey)) { New-Item -Path $dataKey -Force | Out-Null }
            Set-ItemProperty -Path $dataKey -Name "trackingMode" -Value "unlimited" -Force

            $featKey = "$root\appSettings\data\features"
            if (-not (Test-Path $featKey)) { New-Item -Path $featKey -Force | Out-Null }
            Set-ItemProperty -Path $featKey -Name "screenshots" -Value "1" -Force
            Set-ItemProperty -Path $featKey -Name "screencast" -Value "1" -Force
            Set-ItemProperty -Path $featKey -Name "realTimeTrack" -Value "1" -Force
            Set-ItemProperty -Path $featKey -Name "application_usage" -Value "1" -Force
            Set-ItemProperty -Path $featKey -Name "keystrokes" -Value "1" -Force
            Set-ItemProperty -Path $featKey -Name "web_usage" -Value "1" -Force

            if ($cfg.mode -eq "office" -and $email) {
                $authPath = "$root\auth"
                if (-not (Test-Path $authPath)) { New-Item -Path $authPath -Force | Out-Null }
                Set-ItemProperty -Path $authPath -Name "email" -Value $email -Force
                if ($cryptoPass) {
                    Set-ItemProperty -Path $authPath -Name "crypto_password" -Value $cryptoPass -Force
                }
                if ($accessToken) {
                    Set-ItemProperty -Path $authPath -Name "token" -Value $accessToken -Force
                }
            }
        } catch {}
    }
}

function Invoke-PreAuth($cfg) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $email = $cfg.email
    $pass  = $cfg.password
    $headers = @{
        "Client-Device" = $cfg.computerName
        "X-Device-Id"   = $cfg.deviceId
    }

    # Si falta email en modo office, registrar maquina (el backend devuelve el usuario canonico unico por PC)
    if ($cfg.mode -eq "office" -and (-not $email -or -not $pass)) {
        try {
            $regBody = @{
                macId          = $cfg.deviceId
                organizationId = $cfg.orgId
                username       = if ($env:USERNAME) { $env:USERNAME } else { "Usuario" }
                computerName   = $cfg.computerName
                firstname      = "$($cfg.computerName) -"
                lastname       = if ($env:USERNAME) { $env:USERNAME } else { "Usuario" }
            } | ConvertTo-Json -Compress
            $regRes = Invoke-RestMethod -Uri "$($cfg.loginBase)/auth/register" -Method Post -Headers $headers -Body $regBody -ContentType "application/json" -TimeoutSec 12 -ErrorAction Stop
            if ($regRes -and $regRes.code -eq 200) {
                if ($regRes.data -and $regRes.data.email) { $email = [string]$regRes.data.email }
                elseif ($regRes.email) { $email = [string]$regRes.email }
                if ($regRes.data -and $regRes.data.crypto_password) { $pass = [string]$regRes.data.crypto_password }
                elseif ($regRes.crypto_password) { $pass = [string]$regRes.crypto_password }
            }
        } catch {
            Write-LauncherLog "Pre-register pendiente: $_"
        }
    }

    if (-not $email) { return $null }

    try {
        $loginBody = @{
            email    = $email
            password = $pass
            macId    = $cfg.deviceId
        } | ConvertTo-Json -Compress
        $res = Invoke-RestMethod -Uri $cfg.loginUrl -Method Post -Headers $headers -Body $loginBody -ContentType "application/json" -TimeoutSec 12 -ErrorAction Stop
        if ($res -and $res.accessToken) {
            return @{
                email       = $email
                password    = $pass
                accessToken = [string]$res.accessToken
                identifier  = if ($res.identifier) { [string]$res.identifier } else { $cfg.orgId }
                userId      = $res.user_id
            }
        }
    } catch {
        Write-LauncherLog "Pre-login pendiente ($email): $_"
    }
    return $null
}

function Start-AuxModules {
    if (Test-Path $StreamPath) {
        $sp = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*live-stream.ps1*' }
        if (-not $sp) {
            Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$StreamPath`"" -WorkingDirectory $BaseDir -WindowStyle Hidden
            Write-LauncherLog "Modulo live-stream.ps1 iniciado."
        }
    }
    if (Test-Path $DlpPath) {
        $dp = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*dlp-monitor.ps1*' }
        if (-not $dp) {
            Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$DlpPath`"" -WorkingDirectory $BaseDir -WindowStyle Hidden
            Write-LauncherLog "Modulo dlp-monitor.ps1 iniciado."
        }
    }
}

function Start-AgentClean($reason) {
    if (-not (Test-Path $ExePath)) { return }
    # Eliminar archivos de bloqueo si el agente no esta corriendo
    $running = Get-Process -Name "aca-agent","empmonitor" -ErrorAction SilentlyContinue
    if (-not $running) {
        foreach ($lf in @("planExpiryFile.txt", "EmployeeTimestamp.txt")) {
            $p = Join-Path $BaseDir $lf
            if (Test-Path $p) { Remove-Item -Path $p -Force -ErrorAction SilentlyContinue }
        }
        Start-Process -FilePath $ExePath -WorkingDirectory $BaseDir
        Write-LauncherLog "aca-agent.exe iniciado ($reason) con WorkingDirectory=$BaseDir"
    }
}

Write-LauncherLog "=== Iniciando ACA Advisor Launcher v3.0.6 (PC=$($env:COMPUTERNAME), User=$($env:USERNAME)) ==="

$cfg = Get-LauncherConfig
Start-AuxModules

if ($cfg.mode -eq "personal") {
    # Modo visible: asegurar endpoints en HKCU y lanzar UI de login de inmediato
    Sync-UserRegistry $cfg $cfg.email $cfg.password "" $cfg.orgId
    Start-AgentClean "arranque modo visible"
} else {
    # Modo office (silencioso): esperar a que red y servidor respondan y obtener token fresco
    # ANTES de lanzar aca-agent.exe (evita el bloqueo permanente 403 al encender el PC al dia siguiente)
    $authResult = $null
    $attempt = 0
    while (-not $authResult) {
        $attempt++
        $cfg = Get-LauncherConfig
        $authResult = Invoke-PreAuth $cfg
        if ($authResult) {
            Sync-UserRegistry $cfg $authResult.email $authResult.password $authResult.accessToken $authResult.identifier
            Write-LauncherLog "Pre-autenticacion exitosa en intento #$attempt (user_id=$($authResult.userId), email=$($authResult.email))"
            # Si existia una instancia huerfana arrancada antes de obtener token, reiniciarla con el token fresco
            $existing = Get-Process -Name "aca-agent","empmonitor" -ErrorAction SilentlyContinue
            if ($existing) {
                $existing | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            Start-AgentClean "arranque con token fresco"
            break
        }
        if ($attempt -eq 1 -or ($attempt % 4 -eq 0)) {
            Write-LauncherLog "Esperando conectividad con servidor $($cfg.server) (intento #$attempt)..."
        }
        Start-Sleep -Seconds 15
    }
}

# Watchdog continuo: refrescar token, vigilar conectividad y recuperar procesos si caen
$lastTokenSync = Get-Date
$serverWasDown = $false
$downSince = $null

while ($true) {
    Start-Sleep -Seconds 60
    try {
        $cfg = Get-LauncherConfig
        Start-AuxModules

        $agentProc = Get-Process -Name "aca-agent","empmonitor" -ErrorAction SilentlyContinue
        $now = Get-Date

        if ($cfg.mode -eq "office") {
            $needsRefresh = (-not $agentProc) -or $serverWasDown -or (($now - $lastTokenSync).TotalMinutes -ge 30)
            if ($needsRefresh) {
                $authResult = Invoke-PreAuth $cfg
                if ($authResult) {
                    Sync-UserRegistry $cfg $authResult.email $authResult.password $authResult.accessToken $authResult.identifier
                    $lastTokenSync = $now

                    # Si el servidor estuvo caido >10 min y volvio, reiniciar aca-agent.exe una vez con token fresco
                    if ($serverWasDown -and $downSince -and (($now - $downSince).TotalMinutes -ge 10)) {
                        Write-LauncherLog "Servidor recuperado tras desconexion prolongada; reiniciando aca-agent.exe con token fresco."
                        if ($agentProc) {
                            $agentProc | Stop-Process -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 2
                        }
                        $agentProc = $null
                    }
                    $serverWasDown = $false
                    $downSince = $null
                } else {
                    if (-not $serverWasDown) {
                        $serverWasDown = $true
                        $downSince = $now
                        Write-LauncherLog "Servidor $($cfg.server) temporalmente inalcanzable; monitoreando recuperacion..."
                    }
                }
            }

            if (-not $agentProc) {
                # Verificar que exista token en HKCU antes de relanzar
                $curTok = (Get-ItemProperty -Path "HKCU:\Software\screen\empm\auth" -Name "token" -ErrorAction SilentlyContinue).token
                if ($curTok -and $curTok.Length -gt 10) {
                    Start-AgentClean "watchdog recuperacion"
                }
            }
        } else {
            if (-not $agentProc) {
                Start-AgentClean "watchdog modo visible"
            }
        }
    } catch {
        Write-LauncherLog "Error en ciclo watchdog: $_"
    }
}
