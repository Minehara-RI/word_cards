<#
    .SYNOPSIS
    从 pubspec.yaml 的 version: 生成 lib\src\app_version.dart。

    版本号只有一个来源（pubspec.yaml），界面里显示的那个常量是生成出来的，
    不要手改。打包脚本会先跑这一步；test\app_version_test.dart 负责揪出忘了重新生成的提交。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $repo 'pubspec.yaml'
$pubspec = Get-Content $pubspecPath -Raw
$match = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?)')
if (-not $match.Success) { throw "pubspec.yaml 里读不到 version：$pubspecPath" }
$version = $match.Groups[1].Value

$target = Join-Path $repo 'lib\src\app_version.dart'
$content = @"
// 由 scripts\gen_version.ps1 从 pubspec.yaml 生成，不要手改。
// 打包脚本会重新生成；test\app_version_test.dart 会核对它有没有过期。
const String kAppVersion = '$version';
"@
Set-Content -Path $target -Value $content -Encoding utf8 -NoNewline

Write-Host ("  版本号 {0} -> lib\src\app_version.dart" -f $version) -ForegroundColor Green
