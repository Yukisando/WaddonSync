#define MyAppName "WaddonSync"
#define MyAppPublisher "WaddonSync"
#define MyAppURL "https://github.com/Yukisando/WaddonSync"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "WaddonSync-Installer"
#endif

[Setup]
AppId={{C95A7A4B-EA8E-4A26-BEF5-EEAFEE128C34}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableDirPage=no
DisableProgramGroupPage=yes
OutputBaseFilename={#MyOutputBaseFilename}
OutputDir=..
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\waddonsync.exe
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\waddonsync.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\waddonsync.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\waddonsync.exe"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
