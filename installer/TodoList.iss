#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "TodoList"
#define MyAppPublisher "TodoList"
#define MyAppExeName "todolist.exe"
#define MyAppReleaseDir "..\build\windows\x64\runner\Release"
#define VCRedistUrl "https://aka.ms/vc14/vc_redist.x64.exe"

[Setup]
AppId={{8C0E0A0D-0A3C-4DF4-BF1C-7C8F6C3D4A21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=output
OutputBaseFilename=TodoList-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupArchitecture=x64
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]
Source: "{#MyAppReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function IsVCRedistInstalled(): Boolean;
var
  Installed: Cardinal;
begin
  Result :=
    RegQueryDWordValue(
      HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Installed',
      Installed
    ) and (Installed = 1);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  InstallerPath: String;
  ResultCode: Integer;
begin
  Result := '';
  if IsVCRedistInstalled() then
    exit;

  try
    DownloadTemporaryFile(
      '{#VCRedistUrl}',
      'vc_redist.x64.exe',
      '',
      nil
    );
    InstallerPath := ExpandConstant('{tmp}\vc_redist.x64.exe');
  except
    Result := '无法下载 Microsoft Visual C++ x64 运行库。请检查网络后重试，或手动安装后再继续。';
    exit;
  end;

  if not Exec(
    InstallerPath,
    '/install /quiet /norestart',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    Result := '无法启动 Microsoft Visual C++ x64 运行库安装程序。';
    exit;
  end;

  if (ResultCode <> 0) and (ResultCode <> 3010) then
    Result := 'Microsoft Visual C++ x64 运行库安装失败，错误码：' +
      IntToStr(ResultCode) + '。';
end;
