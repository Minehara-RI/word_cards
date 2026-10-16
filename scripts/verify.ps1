<#
    .SYNOPSIS
    提交前 / 打包前的完整体检：analyze + 全量单元测试 + Windows 集成测试。

    .PARAMETER SkipIntegration
    只跑 analyze 和单元测试（集成测试要起真实窗口，慢）。

    .EXAMPLE
    pwsh -File scripts\verify.ps1
#>
[CmdletBinding()]
param(
    [switch] $SkipIntegration
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"

Write-Host '== flutter analyze ==' -ForegroundColor Cyan
Invoke-Flutter analyze

Write-Host '== flutter test ==' -ForegroundColor Cyan
Invoke-Flutter test

if (-not $SkipIntegration) {
    Write-Host '== integration_test (Windows) ==' -ForegroundColor Cyan
    Invoke-Flutter test integration_test/app_test.dart -d windows
    # 集成测试会把 Debug 可执行文件换成测试宿主，跑完重建回真正的应用，
    # 否则手动启动 build\windows\...\word_cards.exe 打开的是测试进程。
    Write-Host '== 重建 Windows Debug（集成测试会覆盖 exe） ==' -ForegroundColor Cyan
    Invoke-Flutter build windows --debug
}

Write-Host '全部通过。' -ForegroundColor Green
