<#
    .SYNOPSIS
    出 Android release APK，产物复制到 dist\。

    .PARAMETER Split
    按 ABI 拆分成多个 APK（体积小，但要分发多份）。默认出通用包。

    .EXAMPLE
    pwsh -File scripts\build_apk.ps1
    pwsh -File scripts\build_apk.ps1 -Split
#>
[CmdletBinding()]
param(
    [switch] $Split
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"

$dist = Join-Path $script:RepoRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$args = @('build', 'apk', '--release')
if ($Split) { $args += '--split-per-abi' }

Write-Host "== flutter $($args -join ' ') ==" -ForegroundColor Cyan
Invoke-Flutter @args

$apkDir = Join-Path $script:RepoRoot 'build\app\outputs\flutter-apk'
if (-not (Test-Path $apkDir)) {
    throw "找不到 APK 输出目录：$apkDir"
}

# release 默认（未拆分）叫 app-release.apk；拆分后是 app-<abi>-release.apk。
$built = Get-ChildItem $apkDir -Filter '*.apk' -File |
    Where-Object { $_.Name -like '*release*' }
if (-not $built) { throw "在 $apkDir 里没找到任何 release APK" }

# 版本号从 pubspec.yaml 读，产物名带上版本，方便和安装包对得上。
$pubspec = Get-Content (Join-Path $script:RepoRoot 'pubspec.yaml') -Raw
$version = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Groups[1].Value
if (-not $version) { $version = '0.0.0' }

foreach ($apk in $built) {
    # app-release.apk -> word_cards-1.0.0.apk；拆分包保留 ABI 后缀
    $abi = [regex]::Match($apk.Name, '^app-(.+)-release\.apk$').Groups[1].Value
    $name = if ($abi) { "word_cards-$version-$abi.apk" } else { "word_cards-$version.apk" }
    $target = Join-Path $dist $name
    Copy-Item $apk.FullName $target -Force
    $size = [math]::Round($apk.Length / 1MB, 1)
    Write-Host ("  {0}  ({1} MB)" -f $target, $size) -ForegroundColor Green
}

Write-Host 'APK 完成。' -ForegroundColor Green
