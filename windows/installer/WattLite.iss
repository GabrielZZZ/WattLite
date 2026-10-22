; WattLite Windows installer (Inno Setup 6.5+)
; Build with: .\build-installer.ps1 -PublishDir <path-to-published-app>

#define AppName "WattLite"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef PublishDir
  #define PublishDir "..\..\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{BACB135C-5D62-4516-9629-C1B167CB3760}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Yifan Zhang Gabriel
AppPublisherURL=https://gabrielzzz.github.io/WattLite/
AppSupportURL=https://github.com/GabrielZZZ/WattLite/issues
AppUpdatesURL=https://github.com/GabrielZZZ/WattLite/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=WattLite-{#AppVersion}-windows-x64-setup
SetupIconFile=..\WattLite\Assets\WattLite.ico
UninstallDisplayIcon={app}\WattLite.exe
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no
AllowNoIcons=yes
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=Yifan Zhang Gabriel
VersionInfoDescription={#AppName} Setup
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoCopyright=Copyright (C) 2026 Yifan Zhang Gabriel

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "README-installed.txt"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\WattLite.exe"; WorkingDir: "{app}"; Comment: "Live power monitor"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\WattLite.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\WattLite.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
