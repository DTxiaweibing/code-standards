#Requires -Version 5.1
<#
全局 pre-commit 门禁：只检查本次提交涉及的代码文件，不扫全仓。

判定与 R2 / R3 / R10 对齐：
  - 新文件：文件有效行 > 500 或函数 > 50 直接拦。
  - 存量文件：不要求重写；本次越过 500 行、或已超限文件继续变长、或新增超限函数才拦。
  - 文件首行含 standards-exempt 的由 check-limits.ps1 自行跳过。

用法：由 git 通过 core.hooksPath 调用，不需要手工执行。
确实要跳过：git commit --no-verify
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# 统一按 UTF-8 输出：git 钩子常被管道/IDE 调用，中文提示不能跟着控制台代码页走
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$HookDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Checker = [System.IO.Path]::GetFullPath((Join-Path $HookDir '..\skill\code-standards\scripts\check-limits.ps1'))
$MaxFileLines = 500
$MaxFuncLines = 50
$CodeExts = @(
    '.ts', '.tsx', '.mts', '.cts', '.js', '.jsx', '.mjs', '.cjs', '.ets',
    '.java', '.kt', '.kts', '.cs', '.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp',
    '.go', '.rs', '.py'
)

function Invoke-Checker {
    param([string]$File)
    $out = & $Checker -Path $File -Json -NoFail 2>$null
    if (-not $out) { return $null }
    return (($out | Out-String) | ConvertFrom-Json)
}

# 把检查报告压成“文件有效行 + 超限函数签名”，便于与 HEAD 版本对比
function Get-ViolationMap {
    param($Report)
    $map = [pscustomobject]@{ FileLines = -1; Funcs = @{} }
    if ($null -eq $Report) { return $map }
    $fileHits = @($Report.fileViolations | Where-Object { $null -ne $_ })
    if ($fileHits.Count -gt 0) { $map.FileLines = [int]$fileHits[0].EffectiveLines }
    foreach ($hit in @($Report.functionViolations)) {
        if ($null -eq $hit) { continue }
        $sig = ($hit.Signature -replace '\s+', ' ').Trim()
        $map.Funcs[$sig] = [int]$hit.Lines
    }
    return $map
}

# 用 git show 取 HEAD 版本写到临时文件，再交给同一个 checker 量一遍
function Get-HeadViolationMap {
    param([string]$RelPath)
    $suffix = [System.IO.Path]::GetExtension($RelPath)
    $tmp = Join-Path $env:TEMP ('cs-head-' + [guid]::NewGuid().ToString('N') + $suffix)
    try {
        $raw = & git show "HEAD:$RelPath" 2>$null
        $text = if ($raw -is [array]) { $raw -join "`n" } else { [string]$raw }
        [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false)))
        return (Get-ViolationMap (Invoke-Checker -File $tmp))
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Add-NewFileProblems {
    param([string]$Path, $Cur, $Problems)
    if ($Cur.FileLines -gt $MaxFileLines) {
        $Problems.Add("$Path : 新文件有效行 $($Cur.FileLines) > $MaxFileLines（R3）")
    }
    foreach ($sig in $Cur.Funcs.Keys) {
        if ($Cur.Funcs[$sig] -gt $MaxFuncLines) {
            $Problems.Add("$Path : 新文件函数 $sig $($Cur.Funcs[$sig]) 行 > $MaxFuncLines（R2）")
        }
    }
}

function Add-ExistingFileProblems {
    param([string]$Path, $Cur, $Head, $Problems)
    if ($Cur.FileLines -gt 0) {
        if ($Head.FileLines -lt 0) {
            $Problems.Add("$Path : 有效行 $($Cur.FileLines) > $MaxFileLines，本次越过上限（R3）")
        } elseif ($Cur.FileLines -gt $Head.FileLines) {
            $Problems.Add("$Path : 存量超限文件又变长 $($Head.FileLines) -> $($Cur.FileLines)（R3）")
        }
    }
    foreach ($sig in $Cur.Funcs.Keys) {
        if (-not $Head.Funcs.ContainsKey($sig)) {
            $Problems.Add("$Path : 新增超限函数 $sig $($Cur.Funcs[$sig]) 行 > $MaxFuncLines（R2）")
        }
    }
}

function Get-StagedRows {
    return @(& git -c core.quotepath=false diff --cached --name-status --diff-filter=ACMR 2>$null)
}

function Test-CodeFile {
    param([string]$Path)
    return ($CodeExts -contains [System.IO.Path]::GetExtension($Path).ToLower())
}

function Write-GateFailure {
    param($Problems)
    Write-Host ''
    Write-Host '[code-standards] 提交被拦截：' -ForegroundColor Red
    foreach ($item in $Problems) { Write-Host "  - $item" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '处理：拆分/提取出小文件或小函数后重试；一次性交付物按 R10 在文件首行写 standards-exempt。' -ForegroundColor Cyan
    Write-Host '确实要跳过本次检查：git commit --no-verify' -ForegroundColor DarkGray
    Write-Host ''
}

$repoRoot = & git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) { exit 0 }

Push-Location $repoRoot
try {
    if (-not (Test-Path -LiteralPath $Checker)) {
        Write-Host "[code-standards] 找不到检查脚本，跳过：$Checker" -ForegroundColor DarkYellow
        exit 0
    }
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($row in (Get-StagedRows)) {
        $parts = $row -split "`t"
        if ($parts.Count -lt 2) { continue }
        $status = $parts[0].Substring(0, 1)
        $path = $parts[-1]
        $headPath = if ($parts.Count -ge 3) { $parts[1] } else { $path }
        if (-not (Test-CodeFile -Path $path)) { continue }
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $cur = Get-ViolationMap (Invoke-Checker -File $path)
        if ($status -eq 'A') {
            Add-NewFileProblems -Path $path -Cur $cur -Problems $problems
        } else {
            $head = Get-HeadViolationMap -RelPath $headPath
            Add-ExistingFileProblems -Path $path -Cur $cur -Head $head -Problems $problems
        }
    }
    if ($problems.Count -eq 0) { exit 0 }
    Write-GateFailure -Problems $problems
    exit 1
} finally {
    Pop-Location
}
