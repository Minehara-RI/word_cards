<#
    .SYNOPSIS
    用 Inno Setup 把 build\windows\...\Release 打成单文件安装包。

    需要先跑 scripts\build_windows.ps1，并且本机装了 Inno Setup 6
    （默认找 C:\Program Files (x86)\Inno Setup 6\ISCC.exe，可用 -Iscc 指定）。

    .PARAMETER AppDir
    写进安装包里的默认安装目录（用户装的时候还能在向导里改）。
    不传就用 packaging\word_flashcards.iss 里的默认值 D:\Program Files\word_flashcards。

    .EXAMPLE
    pwsh -File scripts\build_installer.ps1
    pwsh -File scripts\build_installer.ps1 -AppDir 'E:\Apps\word_flashcards'
#>
[CmdletBinding()]
param(
    [string] $Iscc,
    [string] $AppDir
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"

$releaseDir = Join-Path $script:RepoRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) {
    throw "先跑 scripts\build_windows.ps1（找不到 $releaseDir）"
}

$iss = Join-Path $script:RepoRoot 'packaging\word_flashcards.iss'
if (-not (Test-Path $iss)) { throw "找不到 Inno Setup 脚本：$iss" }

if (-not $Iscc) {
    $candidates = @(
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe',
        # winget 默认按用户安装时装到这里
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    $Iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path $Iscc)) {
    throw @'
没找到 Inno Setup 6 的 ISCC.exe。
装一个（winget install JRSoftware.InnoSetup）或者用参数指定：
    pwsh -File scripts\build_installer.ps1 -Iscc "路径\ISCC.exe"
'@
}

$dist = Join-Path $script:RepoRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# 版本号只有一个来源：pubspec.yaml 的 version: x.y.z+n，去掉 +n 的构建号。
$pubspec = Get-Content (Join-Path $script:RepoRoot 'pubspec.yaml') -Raw
$version = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Groups[1].Value
if (-not $version) { throw 'pubspec.yaml 里读不到 version' }

$defines = @("/DMyAppVersion=$version")
if ($AppDir) { $defines += "/DMyAppDir=$AppDir" }

Write-Host "== ISCC $iss  (版本 $version$(if ($AppDir) { "，默认目录 $AppDir" })) ==" -ForegroundColor Cyan
& $Iscc @defines $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup 编译失败（退出码 $LASTEXITCODE）" }

$setup = Get-ChildItem $dist -Filter 'word_flashcards-setup-*.exe' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($setup) {
    $mb = [math]::Round($setup.Length / 1MB, 1)
    Write-Host ("  安装包：{0}  ({1} MB)" -f $setup.FullName, $mb) -ForegroundColor Green
}
