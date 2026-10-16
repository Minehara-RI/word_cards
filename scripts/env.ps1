<#
    工具链路径统一放在这里，其它脚本都 dot-source 本文件。

    用法：
        . "$PSScriptRoot\env.ps1"

    取值顺序：环境里已设好的同名变量 → 下面这组默认路径 → PATH。
    换机器时改下面这五行即可；提前把环境变量设好，脚本就一个字都不用动。

    每个目录都要「里面真的有对应的文件」才算数，找不到就直接抛错，
    免得后面报一堆看不懂的构建错误。
#>

# ---- 默认路径（换机器时改这里）----
$DefaultFlutterRoot = 'D:\ProgramData\flutter'
$DefaultJavaHome    = 'D:\ProgramData\jdk-21'
$DefaultAndroidHome = 'D:\ProgramData\android-sdk'
$DefaultPubCache    = 'D:\ProgramData\pub-cache'
$DefaultGradleHome  = 'D:\ProgramData\gradle-home'

function Resolve-ToolDir {
    <#
        .SYNOPSIS
        先看环境变量、再看默认路径；两处都要「目录里确实有 $Marker」才算数。
        都找不到就返回 $null，由调用方决定是报错还是退回 PATH。
    #>
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Default,
        [Parameter(Mandatory = $true)][string] $Marker
    )
    $current = [Environment]::GetEnvironmentVariable($Name)
    if ($current -and (Test-Path (Join-Path $current $Marker))) { return $current }
    if (Test-Path (Join-Path $Default $Marker)) { return $Default }
    return $null
}

$toolJavaHome = Resolve-ToolDir 'JAVA_HOME' $DefaultJavaHome 'bin\java.exe'
if (-not $toolJavaHome) {
    throw "找不到 JDK：环境变量 JAVA_HOME 与 $DefaultJavaHome 都不对（改 scripts\env.ps1）"
}
$env:JAVA_HOME = $toolJavaHome

$toolAndroidHome = Resolve-ToolDir 'ANDROID_HOME' $DefaultAndroidHome 'platform-tools'
if ($toolAndroidHome) {
    $env:ANDROID_HOME = $toolAndroidHome
    $env:ANDROID_SDK_ROOT = $toolAndroidHome
} else {
    Write-Warning "找不到 Android SDK：只做 Windows 构建与测试不受影响（改 scripts\env.ps1）"
}

$toolPubCache = Resolve-ToolDir 'PUB_CACHE' $DefaultPubCache 'hosted'
$env:PUB_CACHE = if ($toolPubCache) { $toolPubCache } else { $DefaultPubCache }

$toolGradleHome = Resolve-ToolDir 'GRADLE_USER_HOME' $DefaultGradleHome 'caches'
$env:GRADLE_USER_HOME = if ($toolGradleHome) { $toolGradleHome } else { $DefaultGradleHome }

# Flutter：默认路径优先，其次 PATH 上的 flutter。
$flutterRoot = Resolve-ToolDir 'FLUTTER_ROOT' $DefaultFlutterRoot 'bin\flutter.bat'
if ($flutterRoot) {
    $script:FlutterBat = Join-Path $flutterRoot 'bin\flutter.bat'
} else {
    $onPath = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if (-not $onPath) { $onPath = Get-Command flutter -ErrorAction SilentlyContinue }
    if (-not $onPath) {
        throw "找不到 Flutter：FLUTTER_ROOT、$DefaultFlutterRoot 与 PATH 里都没有（改 scripts\env.ps1）"
    }
    $script:FlutterBat = $onPath.Source
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
