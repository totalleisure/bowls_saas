#ifndef ReleaseDir
  #error ReleaseDir must name the verified Windows Release bundle
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef RuntimeDir
  #error RuntimeDir must name the matching Visual C++ x64 CRT directory
#endif
#ifndef AppVersion
  #define AppVersion "1.5.5"
#endif
#ifndef BuildNumber
  #define BuildNumber "26"
#endif
#if GetFileVersion(ReleaseDir + "\bowls_saas.exe") != AppVersion + "." + BuildNumber
  #error The executable version does not match the installer version
#endif

[Setup]
AppId={{DAFE379D-7B3A-4E44-AE55-A62CB077F082}
AppName=Total Leisure Bowls
AppVersion={#AppVersion}
AppVerName=Total Leisure Bowls {#AppVersion} (build {#BuildNumber})
AppPublisher=Total Leisure
VersionInfoVersion={#AppVersion}.{#BuildNumber}
VersionInfoProductName=Total Leisure Bowls
DefaultDirName={localappdata}\Programs\Total Leisure Bowls
DefaultGroupName=Total Leisure Bowls
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayIcon={app}\bowls_saas.exe
OutputDir={#OutputDir}
OutputBaseFilename=Total-Leisure-Bowls-{#AppVersion}-build-{#BuildNumber}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
; App-local Visual C++ runtime makes installation possible without elevation.
Source: "{#RuntimeDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Total Leisure Bowls"; Filename: "{app}\bowls_saas.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Total Leisure Bowls"; Filename: "{app}\bowls_saas.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\bowls_saas.exe"; Description: "Open Total Leisure Bowls"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
