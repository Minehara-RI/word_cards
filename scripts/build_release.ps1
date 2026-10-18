<#
    .SYNOPSIS
    一步出齐所有发布产物：体检 -> APK -> Windows 免安装包 -> Windows 安装包。

    产物都在 dist\：
        word_cards-<版本>.apk            手机装这个
        word_cards-win-x64\              免安装目录
        word_cards-win-x64.zip            免安装压缩包
        word_cards-setup-<版本>.exe       电脑双击装这个

    .PARAMETER SkipVerify
    跳过 analyze + 测试（赶时间时用，不建议）。

    .PARAMETER SkipInstaller
    不出 Windows 安装包（本机没装 Inno Setup 时用）。

    .PARAMETER DeployTo
    把 Windows 那份程序再放到指定目录（exe 在最外层，双击就跑），
    适合放在 D:\word_cards 这种一眼能看见的浅位置。透传给 build_windows.ps1。

    .EXAMPLE
    pwsh -File scripts\build_release.ps1
    pwsh -File scripts\build_release.ps1 -DeployTo D:\word_cards
#>
[CmdletBinding()]
param(
    [switch] $SkipVerify,
    [switch] $SkipInstaller,
    [string] $DeployTo,
    [string] $AppDir
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"

$started = Get-Date

if (-not $SkipVerify) {
    & "$PSScriptRoot\verify.ps1"
}

& "$PSScriptRoot\build_apk.ps1"
& "$PSScriptRoot\build_windows.ps1" -Installer:(-not $SkipInstaller) -DeployTo $DeployTo -AppDir $AppDir

$dist = Join-Path $script:RepoRoot 'dist'
$elapsed = (Get-Date) - $started

Write-Host ''
Write-Host '=== dist\ ===' -ForegroundColor Cyan
Get-ChildItem $dist | Sort-Object Name | ForEach-Object {
    if ($_.PSIsContainer) {
        $mb = [math]::Round(((Get-ChildItem $_.FullName -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
        Write-Host ("  {0,-34} {1,8} MB" -f ($_.Name + '\'), $mb)
    } else {
        Write-Host ("  {0,-34} {1,8} MB" -f $_.Name, [math]::Round($_.Length / 1MB, 1))
    }
}
Write-Host ''
Write-Host ("全部完成，用时 {0:mm\:ss}。" -f $elapsed) -ForegroundColor Green
