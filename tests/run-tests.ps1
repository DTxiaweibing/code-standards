#Requires -Version 5.1
<#
.SYNOPSIS
    check-limits.ps1 的 golden 测试（零依赖，不装 Pester）。

.DESCRIPTION
    fixture 刻意写得很小，通过 -MaxFileLines / -MaxFuncLines 压低阈值来构造场景，
    避免仓库里出现几百行的大文件。

    覆盖点：
      - 大括号语言 / Python 的函数长度识别
      - 注释、空行、单独收尾括号不计入有效行
      - C/C++ 预处理指令 # 计入代码（不是注释）
      - 豁免声明在第 1 行、shebang 之后的第 2 行都能识别
      - 未豁免的长函数仍会报错（对照组）
      - 模板串 / C++ 原生串的单个花括号不破坏函数帧（两个方向都不漏报）
      - C 的解引用行计入代码，块注释续行仍算注释

.EXAMPLE
    pwsh ./tests/run-tests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Checker = [System.IO.Path]::GetFullPath(
    (Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'skill') 'code-standards') 'scripts/check-limits.ps1'))
if (-not (Test-Path -LiteralPath $Checker)) { throw "找不到 check-limits.ps1: $Checker" }

$script:passed = 0
$script:failed = 0
$script:failures = New-Object System.Collections.Generic.List[string]

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        $script:failed++
        $script:failures.Add("$Message：期望 $Expected，实际 $Actual")
        Write-Host ("  FAIL  {0}（期望 {1}，实际 {2}）" -f $Message, $Expected, $Actual) -ForegroundColor Red
    } else {
        $script:passed++
    }
}

function Invoke-CheckerJson {
    param([string]$Path, [int]$MaxFile, [int]$MaxFunc)
    $raw = & $Checker -Path $Path -Json -NoFail -MaxFileLines $MaxFile -MaxFuncLines $MaxFunc | Out-String
    return ($raw | ConvertFrom-Json)
}

function Test-Case {
    param(
        [string]$Name,
        [string]$Fixture,
        [int]$MaxFile,
        [int]$MaxFunc,
        [int]$Scanned,
        [int]$Skipped,
        [int]$FileHits,
        [int]$FuncHits
    )
    Write-Host ("- {0}" -f $Name)
    $path = Join-Path $PSScriptRoot (Join-Path 'fixtures' $Fixture)
    if (-not (Test-Path -LiteralPath $path)) {
        $script:failed++
        $script:failures.Add("$Name：fixture 不存在 $path")
        Write-Host "  FAIL  fixture 不存在" -ForegroundColor Red
        return
    }
    try {
        $data = Invoke-CheckerJson -Path $path -MaxFile $MaxFile -MaxFunc $MaxFunc
    } catch {
        $script:failed++
        $script:failures.Add("$Name：JSON 解析失败 - $($_.Exception.Message)")
        Write-Host "  FAIL  JSON 解析失败" -ForegroundColor Red
        return
    }
    Assert-Equal $data.scanned $Scanned "$Name / scanned"
    Assert-Equal $data.skipped $Skipped "$Name / skipped"
    Assert-Equal @($data.fileViolations).Count $FileHits "$Name / fileViolations"
    Assert-Equal @($data.functionViolations).Count $FuncHits "$Name / functionViolations"
}

Write-Host "check-limits golden tests" -ForegroundColor Cyan
Write-Host ""

Test-Case -Name '短函数通过' -Fixture 'ts/short.ts' `
    -MaxFile 500 -MaxFunc 50 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 0

Test-Case -Name 'TS 长函数被识别' -Fixture 'ts/long_function.ts' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 1

Test-Case -Name '纯注释行不计入文件长度' -Fixture 'ts/only_comments.ts' `
    -MaxFile 20 -MaxFunc 50 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 0

Test-Case -Name 'C/C++ 预处理指令计入代码行' -Fixture 'cpp/preprocessor.cpp' `
    -MaxFile 20 -MaxFunc 50 -Scanned 1 -Skipped 0 -FileHits 1 -FuncHits 0

Test-Case -Name 'Python 长函数被识别' -Fixture 'py/long_function.py' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 1

Test-Case -Name 'Java 方法内注释不计入有效行' -Fixture 'java/comments_method.java' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 0

Test-Case -Name '首行豁免被跳过' -Fixture 'exemption/exempt_line1.ts' `
    -MaxFile 500 -MaxFunc 3 -Scanned 0 -Skipped 1 -FileHits 0 -FuncHits 0

Test-Case -Name 'shebang 后第 2 行豁免被跳过' -Fixture 'exemption/exempt_after_shebang.js' `
    -MaxFile 500 -MaxFunc 3 -Scanned 0 -Skipped 1 -FileHits 0 -FuncHits 0

Test-Case -Name '未豁免的长函数仍被拦截（对照组）' -Fixture 'exemption/not_exempt_long.ts' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 1

Test-Case -Name '模板串里的 { 不破坏函数帧（不再漏报）' -Fixture 'ts/template_brace.ts' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 1

Test-Case -Name '模板串里的 } 不提前弹帧（不再少算）' -Fixture 'ts/template_close.ts' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 1

Test-Case -Name 'C 解引用行计入代码（不再当块注释）' -Fixture 'cpp/pointer_lines.c' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 1

Test-Case -Name '块注释续行仍不算代码' -Fixture 'cpp/block_comment.c' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 0

Test-Case -Name 'C++ 原生字符串里的花括号不参与匹配' -Fixture 'cpp/raw_string.cpp' `
    -MaxFile 500 -MaxFunc 3 -Scanned 1 -Skipped 0 -FileHits 0 -FuncHits 1

Write-Host ""
if ($script:failed -gt 0) {
    Write-Host ("失败 {0} 项，通过 {1} 项。" -f $script:failed, $script:passed) -ForegroundColor Red
    foreach ($f in $script:failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
Write-Host ("全部通过（{0} 项断言）。" -f $script:passed) -ForegroundColor Green
exit 0
