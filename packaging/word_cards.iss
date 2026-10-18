; 单词卡片（word_cards）Windows 安装包脚本 —— Inno Setup 6
;
; 不要直接双击编译，用仓库里的脚本：
;     pwsh -File scripts\build_installer.ps1
; 它会先确认 build\windows\x64\runner\Release 存在，
; 再把 pubspec.yaml 里的版本号用 /DMyAppVersion=... 传进来。
;
; 产物：dist\word_cards-setup-<版本>.exe

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "单词卡片"
#define MyAppNameEn "word_cards"
#define MyAppExeName "word_cards.exe"
#define MyAppPublisher "minehara"

[Setup]
AppId={{9F2C7B14-5A3E-4D61-9C08-7E4B2A6F1D35}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} 安装程序

; 装进 D 盘的 Program Files（全机器安装）：安装时会弹一次 UAC，点「是」即可。
;     D:\Program Files\word_cards
; 不写 {autopf}：那是系统盘（C 盘）的 Program Files，这里要的是 D 盘。
; 路径放在 ISPP 变量里，换机器/换盘可以覆盖：
;     ISCC /DMyAppDir="E:\Program Files\word_cards" packaging\word_cards.iss
#ifndef MyAppDir
  #define MyAppDir "D:\Program Files\word_cards"
#endif
DefaultDirName={#MyAppDir}

; 安装目录可以自定义：向导里会显示「选择目标位置」页，想装哪儿直接改。
; 命令行静默安装也可以指定：word_cards-setup-x.y.z.exe /VERYSILENT /DIR="E:\Apps\word_cards"
DisableDirPage=no
; 升级时沿用上次选定的目录，不要每次又跳回默认值。
UsePreviousAppDir=yes
; 开始菜单文件夹：「所有应用」里会有一个「单词卡片」，里面是启动与卸载两个快捷方式。
; admin 安装时 {group} 落在 C:\ProgramData\Microsoft\Windows\Start Menu\Programs\
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline

; 应用是 x64，装到 64 位目录里
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

OutputDir=..\dist
OutputBaseFilename=word_cards-setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; 简体中文是社区翻译，官方安装包里不一定带；带了就用，没带就只出英文界面。
#if FileExists(AddBackslash(CompilerPath) + "Languages\ChineseSimplified.isl")
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif

[CustomMessages]
; 官方安装包不带简体中文语言文件（ChineseSimplified.isl 是社区翻译），
; 装出来的界面是英文；至少把开始菜单里的卸载快捷方式改成中文。
english.UninstallProgram=卸载 %1

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Release 目录整体打包：word_cards.exe + 引擎 dll + data\ 下的资源
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 只清理我们装进去的东西；用户数据在 %APPDATA% 下，卸载不碰。
Type: filesandordirs; Name: "{app}\data"

[Code]
{ 默认装在 D 盘，但机器上要是没有 D 盘，就退回系统盘的 Program Files，
  免得向导一打开就是个建不出来的路径。用户仍然可以自己改。 }
procedure InitializeWizard();
begin
  if not DirExists('D:\') then
    WizardForm.DirEdit.Text := ExpandConstant('{autopf}\{#MyAppNameEn}');
end;
