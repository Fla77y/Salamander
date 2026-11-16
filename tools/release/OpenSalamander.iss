; Open Salamander standalone installer, compiled by Update-Build-Test-Package.ps1.
; Inputs are passed via ISCC /DSourceDir=... /DConfiguration=... /DArchitecture=...
#ifndef SourceDir
  #error "SourceDir preprocessor variable is required."
#endif
#ifndef Configuration
  #error "Configuration preprocessor variable is required."
#endif
#ifndef Architecture
  #error "Architecture preprocessor variable is required."
#endif
#ifndef OutputDir
  #error "OutputDir preprocessor variable is required."
#endif

#if Configuration == "Debug"
  #define EditionName "Open Salamander Debug (INTERNAL TEST ONLY)"
  #define ApplicationId "{{6DEDEAB5-F0EB-4861-87ED-20E92A9459A1}"
#else
  #define EditionName "Open Salamander Release"
  #define ApplicationId "{{B977E157-51E1-4138-86F5-0A42853AA44B}"
#endif

[Setup]
AppId={#ApplicationId}
AppName={#EditionName} {#Architecture}
AppVersion=5.1
AppPublisher=Open Salamander
AppPublisherURL=https://github.com/Fla77y/Salamander
DefaultDirName={localappdata}\Programs\Open Salamander {#Configuration} {#Architecture}
DefaultGroupName={#EditionName} {#Architecture}
UninstallDisplayIcon={app}\salamand.exe
OutputDir={#OutputDir}
OutputBaseFilename=OpenSalamander-{#Configuration}-{#Architecture}-Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
MinVersion=10.0
LicenseFile={#SourceDir}\LICENSE
DisableProgramGroupPage=no
WizardStyle=modern

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#EditionName} {#Architecture}"; Filename: "{app}\salamand.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\{#EditionName} {#Architecture}"; Filename: "{app}\salamand.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\salamand.exe"; Description: "Run Open Salamander"; Flags: nowait postinstall skipifsilent unchecked
