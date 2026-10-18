<#
    .SYNOPSIS
    出 Windows release 版，产物复制到 dist\word_cards-win-x64\。

    .PARAMETER Installer
    额外用 Inno Setup 打成单文件安装包 word_cards-setup-x.y.z.exe（需要装 Inno Setup 6）。

    .PARAMETER DeployTo
    顺手在指定目录再放一份「外面」的程序：word_cards.exe 就在那一层，双击就能跑，
    不用每次翻进 build\windows\x64\runner\Release\。

    目标目录非空时，只有里面已经有 word_cards.exe（即上次的部署）才会先清空再复制；
    否则直接报错，绝不误删别的文件夹。

    .EXAMPLE
    pwsh -File scripts\build_windows.ps1
    pwsh -File scripts\build_windows.ps1 -Installer
    pwsh -File scripts\build_windows.ps1 -DeployTo D:\word_cards
#>
[CmdletBinding()]
param(
    [switch] $Installer,
    [string] $DeployTo
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

if ($DeployTo) {
    # 把程序放到「外面」：浅目录、exe 在最外层，双击即可运行。
    $target = [System.IO.Path]::GetFullPath($DeployTo).TrimEnd('\')
    if ($target -eq $releaseDir.TrimEnd('\') -or $target -eq $portable.TrimEnd('\')) {
        throw "部署目标不能是构建输出目录本身：$target"
    }
    if ($target -eq [System.IO.Path]::GetPathRoot($target).TrimEnd('\')) {
        throw "部署目标不能是盘符根目录：$target"
    }
    if ((Test-Path $target) -and (Get-ChildItem $target -Force | Select-Object -First 1)) {
        if (-not (Test-Path (Join-Path $target 'word_cards.exe'))) {
            throw "目标目录非空，且里面没有 word_cards.exe，看起来不是上次的部署：$target —— 确认后手工清空再跑。"
        }
        Remove-Item $target -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item (Join-Path $releaseDir '*') $target -Recurse -Force
    Write-Host ("  外部程序目录：{0}（双击 {1}）" -f $target, 'word_cards.exe') -ForegroundColor Green
}

if ($Installer) {
    & "$PSScriptRoot\build_installer.ps1"
}

Write-Host 'Windows 构建完成。' -ForegroundColor Green
