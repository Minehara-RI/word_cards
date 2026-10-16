<#
    本机工具链路径统一在这里设置，别的脚本都 dot-source 这个文件。

    用法：
        . "$PSScriptRoot\env.ps1"

    为什么不用系统 PATH：这台机器上的 Flutter / JDK / Android SDK / Gradle
    都装在 D:\ProgramData 下，没有写进用户环境变量。脚本自带一份路径，
    换机器时只改这一个文件。
#>

$env:PUB_CACHE        = 'D:\ProgramData\pub-cache'
$env:JAVA_HOME        = 'D:\ProgramData\jdk-21'
$env:ANDROID_HOME     = 'D:\ProgramData\android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = 'D:\ProgramData\gradle-home'

$script:FlutterBat = 'D:\ProgramData\flutter\bin\flutter.bat'

if (-not (Test-Path $script:FlutterBat)) {
    throw "找不到 Flutter：$script:FlutterBat（改 scripts\env.ps1）"
}

# 仓库根目录（scripts\ 的上一级）。
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Flutter {
    <#
        .SYNOPSIS
        在仓库根目录调用 flutter，参数原样透传，退出码非 0 就抛错。
    #>
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Args)
    Push-Location $script:RepoRoot
    try {
        & $script:FlutterBat @Args
        if ($LASTEXITCODE -ne 0) {
            throw "flutter $($Args -join ' ') 失败（退出码 $LASTEXITCODE）"
        }
    } finally {
        Pop-Location
    }
}
