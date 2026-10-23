; Windows installer for Just (Inno Setup 6). Built in CI:
;   ISCC /DAppVersion=0.2.2 /DSourceDir=<Release folder> /DOutputDir=<dist> just.iss
; Per-user install: no administrator rights, removable from Settings → Apps.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B28DE281-963C-405D-9724-4C0223AC4FD1}
AppName=Just
AppVersion={#AppVersion}
AppPublisher=me0wdes
AppPublisherURL=https://github.com/me0wdes/just
DefaultDirName={localappdata}\Programs\Just
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=Just-Setup-{#AppVersion}
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\day_planner.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
; Tells Explorer to drop its cached icons, so shortcuts show a new app icon
; right after an update.
ChangesAssociations=yes

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Just"; Filename: "{app}\day_planner.exe"
Name: "{autodesktop}\Just"; Filename: "{app}\day_planner.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\day_planner.exe"; Description: "{cm:LaunchProgram,Just}"; Flags: nowait postinstall
