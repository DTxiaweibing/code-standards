#Requires -Version 5.1
<#
.SYNOPSIS
    L1 审查门禁：跑规模检查 + TODO 扫描 + git 状态，输出/追加问题台账。

.DESCRIPTION
    对应规范 R11（审查节奏）。
    - 调用同目录 check-limits.ps1 得到文件/函数超限
    - 扫描 TODO / FIXME / HACK / XXX
    - 有 .git 时统计未提交改动
    - 输出可直接贴进 .review/ledger.md 的表格行；-Append 则直接追加（自动去重、自动续 ID）
    - 去重键 = 类别 + 文件 + 判别项（文件级固定 FILE；函数级用签名；TODO 用文本），
      因此重构挪行不会产生重复条目

.PARAMETER Ledger
    台账文件路径；配合 -Append 使用。不存在时会自动创建表头。

.EXAMPLE
    pwsh scripts/review-check.ps1 -Path . -Ledger .review/ledger.md -Append
#>
[CmdletBinding()]
param(
    [string]$Path = ".",
    [string]$Ledger = "",
    [switch]$Append,
    [switch]$NoFail
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$codeExts = @(".ts", ".tsx", ".js", ".jsx", ".mts", ".cjs", ".ets", ".java", ".kt",
    ".cs", ".c", ".cc", ".cpp", ".h", ".hpp", ".go", ".rs", ".py")
$skipDirPattern = '[\\/](node_modules|\.git|\.gradle|\.idea|build|out|dist|target|bin|obj|venv|\.venv|__pycache__|coverage)[\\/]'

function Get-RelPath {
    param([string]$Full)
    if ($Full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Full.Substring($root.Length).TrimStart('\', '/')
    }
    return $Full
}

function New-Finding {
    param([string]$Category, [string]$Severity, [string]$RelFile, [int]$Line, [string]$Problem, [string]$Discriminator)
    [pscustomobject]@{
        Category = $Category; Severity = $Severity; File = $RelFile; Line = $Line
        Problem = $Problem
        Key = "$Category|$RelFile|$Discriminator"
    }
}

# ---------- 1. 规模检查 ----------
$findings = New-Object System.Collections.Generic.List[object]
$limits = Join-Path $PSScriptRoot "check-limits.ps1"
if (Test-Path -LiteralPath $limits) {
    $raw = & $limits -Path $root -Json -NoFail
    $data = $raw | ConvertFrom-Json
    foreach ($f in $data.fileViolations) {
        $sev = if ($f.EffectiveLines -ge 1000) { "P1" } else { "P2" }
        $findings.Add((New-Finding -Category "file-size" -Severity $sev -RelFile (Get-RelPath $f.File) `
                    -Line 1 -Problem "文件 $($f.EffectiveLines) 有效行 > 500" -Discriminator "FILE")) | Out-Null
    }
    foreach ($f in $data.functionViolations) {
        $sev = if ($f.Lines -ge 100) { "P1" } else { "P2" }
        $findings.Add((New-Finding -Category "func-size" -Severity $sev -RelFile (Get-RelPath $f.File) `
                    -Line $f.Line -Problem "函数 $($f.Lines) 行 > 50（$($f.Signature)）" -Discriminator $f.Signature)) | Out-Null
    }
}

# ---------- 2. TODO 扫描 ----------
$todoPattern = '(?i)\b(TODO|FIXME|HACK|XXX)\b'
$files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $codeExts -contains $_.Extension.ToLower() -and $_.FullName -notmatch $skipDirPattern }
foreach ($file in $files) {
    $lines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $todoPattern) {
            $text = $lines[$i].Trim()
            if ($text.Length -gt 70) { $text = $text.Substring(0, 70) + "…" }
            $findings.Add((New-Finding -Category "lint" -Severity "P3" -RelFile (Get-RelPath $file.FullName) `
                        -Line ($i + 1) -Problem $text -Discriminator $text)) | Out-Null
        }
    }
}

# ---------- 3. git 状态 ----------
$dirty = 0
if (Test-Path -LiteralPath (Join-Path $root ".git")) {
    try { $dirty = @(git -C $root status --porcelain).Count } catch { $dirty = 0 }
}

# ---------- 4. 台账读取：去重键 / 续号 / 已有阻断项 ----------
$existingKeys = @{}
$maxId = 0
$openBlocking = 0
$ledgerPath = $null
if ($Ledger) {
    if ([System.IO.Path]::IsPathRooted($Ledger)) { $ledgerPath = $Ledger }
    else { $ledgerPath = Join-Path $root $Ledger }
}
if ($ledgerPath -and (Test-Path -LiteralPath $ledgerPath)) {
    foreach ($line in [System.IO.File]::ReadAllLines($ledgerPath)) {
        if ($line -notmatch '^\|\s*R-(\d+)') { continue }
        $m = [regex]::Match($line, 'R-(\d+)')
        $n = [int]$m.Groups[1].Value
        if ($n -gt $maxId) { $maxId = $n }

        $cells = $line.Trim('|') -split '\|'
        if ($cells.Count -lt 6) { continue }
        $cat = $cells[2].Trim()
        $loc = $cells[3].Trim().Trim('`')
        $loc = $loc -replace ':\d+$', ''
        $problem = $cells[4].Trim()
        $status = $cells[5].Trim()

        if ($cat -eq 'file-size') { $disc = 'FILE' }
        elseif ($cat -eq 'func-size') {
            $dm = [regex]::Match($problem, '（(.+)）$')
            $disc = if ($dm.Success) { $dm.Groups[1].Value } else { $problem }
        } else { $disc = $problem }

        $existingKeys["$cat|$loc|$disc"] = $true

        if ($cells[1].Trim() -match 'P[01]' -and $status -eq 'open') { $openBlocking++ }
    }
}

# ---------- 5. 生成新行 ----------
$newRows = New-Object System.Collections.Generic.List[object]
foreach ($f in $findings) {
    if ($existingKeys.ContainsKey($f.Key)) { continue }
    $existingKeys[$f.Key] = $true
    $maxId++
    $newRows.Add([pscustomobject]@{
        Id = ("R-{0:000}" -f $maxId); Severity = $f.Severity; Category = $f.Category
        Location = "$($f.File):$($f.Line)"; Problem = $f.Problem
    }) | Out-Null
}

function Format-Row {
    param($R)
    '| {0} | {1} | {2} | `{3}` | {4} | open | | |' -f $R.Id, $R.Severity, $R.Category, $R.Location, ($R.Problem -replace '\|', '\|')
}

$header = @'
# 问题台账（review ledger）

> 由 `review-check.ps1` 生成；规则见 `~/.agents/skills/code-standards/references/review-gate.md`。
> 只增不删；`deferred` 必须写触发条件；P0/P1 禁止延期。

| ID | 级别 | 类别 | 位置 | 问题 | 状态 | 决定/理由 | 触发条件 |
|---|---|---|---|---|---|---|---|
'@

if ($Append -and $ledgerPath) {
    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        $dir = Split-Path -Parent $ledgerPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($ledgerPath, $header + "`n", $utf8NoBom)
    }
    if ($newRows.Count -gt 0) {
        $rowsText = ($newRows | ForEach-Object { Format-Row $_ }) -join "`n"
        $tail = [System.IO.File]::ReadAllText($ledgerPath).TrimEnd()
        [System.IO.File]::WriteAllText($ledgerPath, $tail + "`n" + $rowsText + "`n", $utf8NoBom)
        Write-Host ("台账追加 {0} 条 -> {1}" -f $newRows.Count, $ledgerPath) -ForegroundColor Green
    } else {
        Write-Host "台账无新增条目" -ForegroundColor Green
    }
}

# ---------- 6. 输出 ----------
Write-Host ""
Write-Host ("L1 检查：{0} — 新增 {1} 条，未提交改动 {2} 个文件" -f $root, $newRows.Count, $dirty) -ForegroundColor Cyan
if ($newRows.Count -gt 0) {
    $newRows | Format-Table @{n = 'ID'; e = { $_.Id } }, @{n = '级别'; e = { $_.Severity } },
                             @{n = '类别'; e = { $_.Category } }, @{n = '位置'; e = { $_.Location } },
                             @{n = '问题'; e = { $_.Problem } } -AutoSize | Out-String -Width 220 | Write-Host
}

$blocking = @($newRows | Where-Object { $_.Severity -eq "P0" -or $_.Severity -eq "P1" }).Count + $openBlocking
if ($blocking -gt 0) {
    Write-Host ("阻断项 {0} 条（含台账已有 open P0/P1：{1}）：修完再继续。" -f $blocking, $openBlocking) -ForegroundColor Red
    if (-not $NoFail) { exit 1 }
} else {
    Write-Host "无 P0/P1，可继续。" -ForegroundColor Green
}
