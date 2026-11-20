; ==============================================================================
; ACA ADVISOR S.A.S. - Instalador Corporativo para Windows (Modo Visible / Personal)
; Script de compilación para Inno Setup Compiler (versión 6+)
; ==============================================================================

#define MyAppName "ACA Advisor Agent"
#define MyAppVersion "3.0.6"
#define MyAppPublisher "ACA ADVISOR S.A.S."
#define MyAppURL "https://acaadvisor.com"
#define MyAppExeName "aca-agent.exe"
#define MyAppAssocName MyAppName + " File"
#define MyAppAssocExt ".aca"
#define MyAppAssocKey StringChange(MyAppAssocName, " ", "") + MyAppAssocExt

[Setup]
; Identificador único de aplicación (compartido para evitar instalaciones duplicadas)
AppId={{8B3F9A12-4C7D-4F1E-9A52-8D1C7B2E3F4A}
AppName={#MyAppName} (Visible)
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\ACA Advisor Agent
DefaultGroupName=ACA ADVISOR S.A.S.
DisableProgramGroupPage=yes
LicenseFile=LICENSE.txt
OutputDir=Output
OutputBaseFilename=ACA_Advisor_Agent_Visible_Setup
SetupIconFile=aca-advisor.ico
UninstallDisplayIcon={app}\aca-advisor.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force

; Personalización visual de ACA ADVISOR (Modo Claro y Oscuro)
WizardImageFile=wizard-side.png
WizardImageFileDynamicDark=wizard-side.png
WizardSmallImageFile=logo-isotype.png
WizardSmallImageFileDynamicDark=logo-isotype.png

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "Iniciar automáticamente con Windows (Recomendado)"; GroupDescription: "Configuración del servicio:"

[Dirs]
Name: "{app}\configs"; Permissions: users-readexec
Name: "{app}\failed_screenshots"; Permissions: users-modify
Name: "{app}\logs"; Permissions: users-modify

[Files]
; Archivos del ejecutable (con login y estilos ACA ADVISOR S.A.S.), librerías, register.ps1 y live-stream.ps1
Source: "bin\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Archivos de configuración con marca ACA ADVISOR
Source: "config.js"; DestDir: "{app}\configs"; Flags: ignoreversion
Source: "config.json"; DestDir: "{app}\configs"; Flags: ignoreversion
Source: "aca-advisor.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "logo-horizontal.png"; DestDir: "{app}\assets"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\aca-advisor.ico"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\aca-advisor.ico"

[Registry]
; Inicio automático unificado en arranque de Windows (Launcher Watchdog: Agente Visible + Live Stream + DLP)
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "ACAAdvisorAgent"; Flags: deletevalue
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "ACAAdvisorLiveStream"; Flags: deletevalue
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "ACAAdvisorDLP"; Flags: deletevalue
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "ACAAdvisorLauncher"; ValueData: "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\agent-launcher.ps1"""; Flags: uninsdeletevalue; Tasks: autostart

; El lanzamiento de aca-agent.exe (interfaz visible) y live-stream.ps1 lo gestiona register.ps1 al finalizar ssPostInstall

[Code]
var
  ServerPage: TInputQueryWizardPage;

procedure InitializeWizard;
var
  DefaultHost: String;
begin
  DefaultHost := ExpandConstant('{param:SERVER|192.168.0.155}');
  ServerPage := CreateInputQueryPage(
    wpSelectDir,
    'Servidor Central ACA Advisor (Modo Visible)',
    'Configuración de conexión en modo visible (con interfaz de inicio de sesión)',
    'Verifique o ingrese la dirección IP o dominio del servidor central ACA Advisor:'
  );
  ServerPage.Add('IP o Dominio del Servidor (ej. 192.168.0.155):', False);
  ServerPage.Add('ID de Organización:', False);
  ServerPage.Values[0] := DefaultHost;
  ServerPage.Values[1] := ExpandConstant('{param:ORGID|OjUpRAB}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ServerHost: String;
  OrgId: String;
  ConfigJson: String;
begin
  if CurStep = ssInstall then
  begin
    // Cerrar instancias previas del agente antes de sobrescribir archivos
    Exec('taskkill.exe', '/F /IM aca-agent.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /IM empmonitor.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    // Quitar atributo de solo lectura si existían archivos previos
    Exec('cmd.exe', '/c attrib -r "' + ExpandConstant('{app}\configs\config.js') + '" 2>nul & attrib -r "' + ExpandConstant('{app}\configs\config.json') + '" 2>nul', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;

  if CurStep = ssPostInstall then
  begin
    ServerHost := Trim(ServerPage.Values[0]);
    if ServerHost = '' then
      ServerHost := '192.168.0.155';

    OrgId := Trim(ServerPage.Values[1]);
    if OrgId = '' then
      OrgId := 'OjUpRAB';

    // Generar JSON requerido por el binario C++/Qt en modo "personal" (login visible ACA ADVISOR S.A.S.)
    ConfigJson :=
      '{' + #13#10 +
      '  "id": "' + OrgId + '",' + #13#10 +
      '  "mode": "personal",' + #13#10 +
      '  "api": "http://' + ServerHost + ':3001/api/v1",' + #13#10 +
      '  "login": "http://' + ServerHost + ':3004/api/v3",' + #13#10 +
      '  "pipeline": "http://' + ServerHost + ':3001/api/v1",' + #13#10 +
      '  "realtime": "ws://' + ServerHost + ':3003",' + #13#10 +
      '  "updates": "http://' + ServerHost + ':3004/api/v3"' + #13#10 +
      '}' + #13#10;

    SaveStringToFile(ExpandConstant('{app}\configs\config.js'), ConfigJson, False);
    SaveStringToFile(ExpandConstant('{app}\configs\config.json'), ConfigJson, False);

    // Limpiar archivos de bloqueo residuales
    DeleteFile(ExpandConstant('{app}\planExpiryFile.txt'));
    DeleteFile(ExpandConstant('{app}\EmployeeTimestamp.txt'));
    DeleteFile(ExpandConstant('{app}\dataLog.txt'));

    // Proteger config.js y config.json como solo lectura contra auto-modificaciones
    Exec('cmd.exe', '/c attrib +r "' + ExpandConstant('{app}\configs\config.js') + '" & attrib +r "' + ExpandConstant('{app}\configs\config.json') + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Escribir endpoints principales en la ruta nativa de QSettings (Software\screen\empm)
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'api', 'http://' + ServerHost + ':3001/api/v1');
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'api', 'http://' + ServerHost + ':3001/api/v1');
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'pipeline', 'http://' + ServerHost + ':3001/api/v1');
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'pipeline', 'http://' + ServerHost + ':3001/api/v1');
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'realtime', 'ws://' + ServerHost + ':3003');
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'realtime', 'ws://' + ServerHost + ':3003');
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'login', 'http://' + ServerHost + ':3004/api/v3');
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'login', 'http://' + ServerHost + ':3004/api/v3');
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'updates', 'http://' + ServerHost + ':3004/api/v3');
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'updates', 'http://' + ServerHost + ':3004/api/v3');
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'backend_base', 'http://' + ServerHost + ':3001/api/v1');
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'backend_base', 'http://' + ServerHost + ':3001/api/v1');
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'backend_base_login', 'http://' + ServerHost + ':3004/api/v3');
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'backend_base_login', 'http://' + ServerHost + ':3004/api/v3');
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'update_base_url', 'http://' + ServerHost + ':3004/api/v3');
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'update_base_url', 'http://' + ServerHost + ':3004/api/v3');
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'organization_id', OrgId);
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'organization_id', OrgId);
    RegWriteStringValue(HKCU, 'Software\screen\empm', 'identifier', OrgId);
    RegWriteStringValue(HKLM, 'Software\screen\empm', 'identifier', OrgId);

    // Escribir intervalos optimizados y modo personal (login visible ACA ADVISOR S.A.S.)
    RegWriteDWordValue(HKCU, 'Software\screen\empm\appSettings', 'dataSendingPeriodSec', 30);
    RegWriteDWordValue(HKLM, 'Software\screen\empm\appSettings', 'dataSendingPeriodSec', 30);
    RegWriteDWordValue(HKCU, 'Software\screen\empm\appSettings', 'screenshotQuality', 82);
    RegWriteDWordValue(HKLM, 'Software\screen\empm\appSettings', 'screenshotQuality', 82);
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings', 'mode', 'personal');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings', 'mode', 'personal');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\from_remote', 'account_type', 'personal');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\from_remote', 'account_type', 'personal');
    RegWriteDWordValue(HKCU, 'Software\screen\empm\appSettings\from_remote', 'screenshotPeriodSec', 20);
    RegWriteDWordValue(HKLM, 'Software\screen\empm\appSettings\from_remote', 'screenshotPeriodSec', 20);
    RegWriteDWordValue(HKCU, 'Software\screen\empm\appSettings\from_remote', 'ADUserInfoSendPerSec', 60);
    RegWriteDWordValue(HKLM, 'Software\screen\empm\appSettings\from_remote', 'ADUserInfoSendPerSec', 60);
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data', 'trackingMode', 'unlimited');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\data', 'trackingMode', 'unlimited');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'screenshots', '1');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\data\features', 'screenshots', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'screencast', '1');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\data\features', 'screencast', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'realTimeTrack', '1');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\data\features', 'realTimeTrack', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'application_usage', '1');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\data\features', 'application_usage', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'keystrokes', '1');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\data\features', 'keystrokes', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'web_usage', '1');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\data\features', 'web_usage', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'block_websites', '0');
    RegWriteStringValue(HKLM, 'Software\screen\empm\appSettings\data\features', 'block_websites', '0');

    // Respaldo de compatibilidad en Software\EmpMonitor\EmpMonitor
    RegWriteDWordValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings', 'dataSendingPeriodSec', 30);
    RegWriteDWordValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings', 'screenshotQuality', 50);
    RegWriteStringValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings', 'mode', 'personal');
    RegWriteStringValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings\from_remote', 'account_type', 'personal');
    RegWriteDWordValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings\from_remote', 'screenshotPeriodSec', 20);
    RegWriteDWordValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings\from_remote', 'ADUserInfoSendPerSec', 60);

    // Ejecutar script oficial de configuracion en modo visible (personal), Live Stream y arranque
    Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\register.ps1') + '" -ServerHost "' + ServerHost + '" -OrgId "' + OrgId + '" -Mode "personal"', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
