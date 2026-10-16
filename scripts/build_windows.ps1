<#
    .SYNOPSIS
    出 Windows release 版，产物复制到 dist\word_cards-win-x64\。

    .PARAMETER Installer
    额外用 Inno Setup 打成单文件安装包 word_cards-setup-x.y.z.exe（需要装 Inno Setup 6）。

    .EXAMPLE
    pwsh -File scripts\build_windows.ps1
    pwsh -File scripts\build_windows.ps1 -Installer
#>
[CmdletBinding()]
param(
    [switch] $Installer
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"

$dist = Join-Path $script:RepoRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Write-Host '== flutter build windows --release ==' -ForegroundColor Cyan
Invoke-Flutter build windows --release

$releaseDir = Join-Path $script:RepoRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) {
    throw "找不到 Release 输出目录：$releaseDir"
}

$portable = Join-Path $dist 'word_cards-win-x64'
if (Test-Path $portable) { Remove-Item $portable -Recurse -Force }
New-Item -ItemType Directory -Force -Path $portable | Out-Null
Copy-Item (Join-Path $releaseDir '*') $portable -Recurse -Force

# 顺带留一份 zip，方便不想装东西的人直接用。
$zip = Join-Path $dist 'word_cards-win-x64.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $portable '*') -DestinationPath $zip -Force

$mb = [math]::Round(((Get-ChildItem $portable -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host ("  免安装目录：{0}  ({1} MB)" -f $portable, $mb) -ForegroundColor Green
Write-Host ("  免安装压缩包：{0}" -f $zip) -ForegroundColor Green

if ($Installer) {
    & "$PSScriptRoot\build_installer.ps1"
}

Write-Host 'Windows 构建完成。' -ForegroundColor Green
