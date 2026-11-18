; ==============================================================================
; ACA ADVISOR S.A.S. - Instalador Corporativo para Windows (Modo Silencioso / Office)
; Script de compilación para Inno Setup Compiler (versión 6+)
; ==============================================================================

#define MyAppName "ACA Advisor Agent"
#define MyAppVersion "3.0.2"
#define MyAppPublisher "ACA ADVISOR S.A.S."
#define MyAppURL "https://acaadvisor.com"
#define MyAppExeName "aca-agent.exe"
#define MyAppAssocName MyAppName + " File"
#define MyAppAssocExt ".aca"
#define MyAppAssocKey StringChange(MyAppAssocName, " ", "") + MyAppAssocExt

[Setup]
; Identificador único de aplicación
AppId={{8B3F9A12-4C7D-4F1E-9A52-8D1C7B2E3F4A}
AppName={#MyAppName}
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
OutputBaseFilename=ACA_Advisor_Agent_Setup
SetupIconFile=aca-advisor.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
CloseApplications=force

; Personalización visual de ACA ADVISOR
WizardImageFile=logo-isotype.png
WizardSmallImageFile=logo-isotype.png

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "autostart"; Description: "Iniciar automáticamente con Windows (Recomendado)"; GroupDescription: "Configuración del servicio:"

[Dirs]
Name: "{app}"; Permissions: users-full
Name: "{app}\configs"; Permissions: users-full
Name: "{app}\failed_screenshots"; Permissions: users-full

[Files]
; Archivos del ejecutable y librerías
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
; Inicio automático en arranque de Windows
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "ACAAdvisorAgent"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
; Iniciar la aplicación al finalizar
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

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
    'Servidor Central ACA Advisor',
    'Configuración de conexión en modo corporativo silencioso (sin ventana de login)',
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

    // Generar JSON puro requerido por el binario C++/Qt en modo "office" (sin ventana de login)
    ConfigJson :=
      '{' + #13#10 +
      '  "id": "' + OrgId + '",' + #13#10 +
      '  "mode": "office",' + #13#10 +
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

    // Proteger config.js y config.json como solo lectura contra auto-modificaciones (manipulateConfigJs)
    Exec('cmd.exe', '/c attrib +r "' + ExpandConstant('{app}\configs\config.js') + '" & attrib +r "' + ExpandConstant('{app}\configs\config.json') + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Limpiar caché previa en el Registro de Windows (de instalaciones anteriores)
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Empmonitor');
    RegDeleteKeyIncludingSubkeys(HKLM, 'Software\Empmonitor');
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\screen\empm');
    RegDeleteKeyIncludingSubkeys(HKLM, 'Software\screen\empm');

    // Escribir intervalos optimizados (30s actividad, 20s capturas) en la ruta real de QSettings (Software\screen\empm)
    RegWriteDWordValue(HKCU, 'Software\screen\empm\appSettings', 'dataSendingPeriodSec', 30);
    RegWriteDWordValue(HKCU, 'Software\screen\empm\appSettings', 'screenshotQuality', 50);
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings', 'mode', 'office');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\from_remote', 'account_type', 'office');
    RegWriteDWordValue(HKCU, 'Software\screen\empm\appSettings\from_remote', 'screenshotPeriodSec', 20);
    RegWriteDWordValue(HKCU, 'Software\screen\empm\appSettings\from_remote', 'ADUserInfoSendPerSec', 60);
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data', 'trackingMode', 'unlimited');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'screenshots', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'screencast', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'realTimeTrack', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'application_usage', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'keystrokes', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\appSettings\data\features', 'web_usage', '1');
    RegWriteStringValue(HKCU, 'Software\screen\empm\auth', 'crypto_password', '43d7dbcf81bad521552d1b59e619cced:ede717306619e874100560153a96ecc3');
    RegWriteStringValue(HKLM, 'Software\screen\empm\auth', 'crypto_password', '43d7dbcf81bad521552d1b59e619cced:ede717306619e874100560153a96ecc3');

    // Respaldo de compatibilidad en Software\EmpMonitor\EmpMonitor
    RegWriteDWordValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings', 'dataSendingPeriodSec', 30);
    RegWriteDWordValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings', 'screenshotQuality', 50);
    RegWriteStringValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings', 'mode', 'office');
    RegWriteStringValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings\from_remote', 'account_type', 'office');
    RegWriteDWordValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings\from_remote', 'screenshotPeriodSec', 20);
    RegWriteDWordValue(HKCU, 'Software\EmpMonitor\EmpMonitor\appSettings\from_remote', 'ADUserInfoSendPerSec', 60);

    // Agregar exclusión de la carpeta de instalación en Windows Defender
    Exec('powershell.exe', '-WindowStyle Hidden -Command "Add-MpPreference -ExclusionPath ''' + ExpandConstant('{app}') + '''"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
