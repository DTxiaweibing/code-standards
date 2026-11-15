#Requires -Version 5.1
<#
.SYNOPSIS
    跨语言代码规模检查：文件 ≤ MaxFileLines、函数 ≤ MaxFuncLines（默认 500 / 50）。

.DESCRIPTION
    对应规范 R2（函数 ≤50 行）与 R3（文件 ≤500 行）。
    语言：TS/JS/Java/Kotlin/C/C++/C#/Go/Rust 走大括号匹配；Python 走缩进块。
    只做规模审计，不做风格检查（风格交给 eslint/checkstyle/clang-tidy/ruff）。
    豁免：文件首行含 standards-exempt 的文件直接跳过。

.PARAMETER Path
    要扫描的目录或文件，默认当前目录。

.PARAMETER Json
    以 JSON 输出（便于 CI 解析）。

.PARAMETER NoFail
    有违规也不返回退出码 1（本地看报告时用）。

.EXAMPLE
    pwsh scripts/check-limits.ps1 -Path D:\mixcalc-lab\app\src -NoFail
#>
[CmdletBinding()]
param(
    [string]$Path = ".",
    [int]$MaxFileLines = 500,
    [int]$MaxFuncLines = 50,
    [int]$Top = 15,
    [switch]$Json,
    [switch]$NoFail
)

$ErrorActionPreference = "Stop"

$defaultExts = @(
    ".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs", ".ets",
    ".java", ".kt", ".kts", ".cs",
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp",
    ".go", ".rs", ".py"
)
$skipDirPattern = '[\\/](node_modules|\.git|\.gradle|\.idea|build|out|dist|target|bin|obj|venv|\.venv|__pycache__|coverage|\.next|\.nuxt)[\\/]'

function Get-CleanedLine {
    param(
        [string]$Line,
        [ref]$InBlockComment
    )
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    $quote = [char]0
    while ($i -lt $Line.Length) {
        $c = $Line[$i]
        if ($InBlockComment.Value) {
            if ($c -eq '*' -and ($i + 1) -lt $Line.Length -and $Line[$i + 1] -eq '/') {
                $InBlockComment.Value = $false
                $i += 2
                continue
            }
            $i++
            continue
        }
        if ($quote -ne [char]0) {
            if ($c -eq '\') { $i += 2; continue }
            if ($c -eq $quote) { $quote = [char]0 }
            $i++
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $Line.Length) {
            if ($Line[$i + 1] -eq '/') { break }
            if ($Line[$i + 1] -eq '*') { $InBlockComment.Value = $true; $i += 2; continue }
        }
        if ($c -eq '"' -or $c -eq "'") { $quote = $c; $i++; continue }
        [void]$sb.Append($c)
        $i++
    }
    return $sb.ToString()
}

function Test-IsFunctionHead {
    param([string]$Text)
    $t = $Text.Trim()
    if ($t -eq '') { return $false }
    if ($t -match '^\}|^\}\s*else') { return $false }
    if ($t -match '^\s*(if|for|foreach|while|switch|catch|try|do|else|finally|using|lock|synchronized)\b') { return $false }
    if ($t -match '\b(class|interface|enum|struct|namespace|union|record|@interface)\b') { return $false }
    if ($t -match '^\s*#') { return $false }
    # 匿名内部类实例 new X() { ... } 不是函数
    if ($t -match '\bnew\s+[A-Za-z_][\w\.<>]*\s*\([^)]*\)\s*\{\s*$') { return $false }
    # 必须形如 "...) ... {" 或 "=> {"
    if ($t -match '\)\s*[^;{}]*\{') { return $true }
    if ($t -match '=>\s*\{') { return $true }
    return $false
}

function Get-EffectiveLineCount {
    param([string[]]$Lines, [int]$Start, [int]$End)
    $n = 0
    for ($i = $Start; $i -le $End -and $i -le $Lines.Count; $i++) {
        $l = $Lines[$i - 1].Trim()
        if ($l -eq '') { continue }
        if ($l.StartsWith('//') -or $l.StartsWith('#') -or $l.StartsWith('/*') -or
            $l.StartsWith('*') -or $l.StartsWith('*/') -or $l.StartsWith('--')) { continue }
        if ($l -match '^[\}\)\];,]+$') { continue }
        $n++
    }
    return $n
}

function Get-BraceFunctions {
    param([string[]]$Lines, [int]$MaxFunc)
    $results = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.List[object]
    $inBlock = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $clean = Get-CleanedLine -Line $Lines[$i] -InBlockComment ([ref]$inBlock)
        $opens = ([regex]::Matches($clean, '\{')).Count
        $closes = ([regex]::Matches($clean, '\}')).Count
        for ($k = 0; $k -lt $opens; $k++) {
            $frame = @{ Line = ($i + 1); Text = $Lines[$i] }
            $stack.Add($frame) | Out-Null
        }
        for ($k = 0; $k -lt $closes; $k++) {
            if ($stack.Count -gt 0) {
                $frame = $stack[$stack.Count - 1]
                $stack.RemoveAt($stack.Count - 1)
                if (Test-IsFunctionHead -Text $frame.Text) {
                    $len = ($i + 1) - $frame.Line + 1
                    $eff = Get-EffectiveLineCount -Lines $Lines -Start $frame.Line -End ($i + 1)
                    if ($eff -gt $MaxFunc) {
                        $name = $frame.Text.Trim()
                        if ($name.Length -gt 60) { $name = $name.Substring(0, 60) + '…' }
                        $results.Add([pscustomobject]@{ Line = $frame.Line; Lines = $eff; Signature = $name }) | Out-Null
                    }
                }
            }
        }
    }
    return $results
}

function Get-PythonFunctions {
    param([string[]]$Lines, [int]$MaxFunc)
    $results = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $m = [regex]::Match($Lines[$i], '^(\s*)(async\s+)?def\s+([A-Za-z_]\w*)\s*\(')
        if (-not $m.Success) { continue }
        $indent = $m.Groups[1].Value.Length
        $name = $m.Groups[3].Value
        $end = $Lines.Count
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            $raw = $Lines[$j]
            if ($raw.Trim() -eq '') { continue }
            $ind = $raw.Length - $raw.TrimStart().Length
            if ($ind -le $indent -and $raw.Trim() -notmatch '^[\)\]\}]') {
                $end = $j
                break
            }
        }
        $eff = Get-EffectiveLineCount -Lines $Lines -Start ($i + 1) -End $end
        if ($eff -gt $MaxFunc) {
            $results.Add([pscustomobject]@{ Line = ($i + 1); Lines = $eff; Signature = "def $name(...)" }) | Out-Null
        }
    }
    return $results
}

# ---------- 收集文件 ----------
$targets = @()
if (Test-Path -LiteralPath $Path -PathType Container) {
    $targets = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $defaultExts -contains $_.Extension.ToLower() -and $_.FullName -notmatch $skipDirPattern }
} elseif (Test-Path -LiteralPath $Path) {
    $targets = @(Get-Item -LiteralPath $Path)
} else {
    Write-Error "路径不存在: $Path"
    return
}

$fileViolations = New-Object System.Collections.Generic.List[object]
$funcViolations = New-Object System.Collections.Generic.List[object]
$scanned = 0
$skipped = 0

foreach ($f in $targets) {
    $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
    if ($lines.Count -eq 0) { continue }
    if ($lines[0] -match 'standards-exempt') { $skipped++; continue }

    $scanned++
    $raw = $lines.Count
    $eff = Get-EffectiveLineCount -Lines $lines -Start 1 -End $raw
    if ($eff -gt $MaxFileLines) {
        $fileViolations.Add([pscustomobject]@{
            File = $f.FullName; RawLines = $raw; EffectiveLines = $eff; Over = $eff - $MaxFileLines
        }) | Out-Null
    }

    $funcs = @()
    if ($f.Extension.ToLower() -eq '.py') {
        $funcs = Get-PythonFunctions -Lines $lines -MaxFunc $MaxFuncLines
    } else {
        $funcs = Get-BraceFunctions -Lines $lines -MaxFunc $MaxFuncLines
    }
    foreach ($fn in $funcs) {
        $funcViolations.Add([pscustomobject]@{
            File = $f.FullName; Line = $fn.Line; Lines = $fn.Lines; Signature = $fn.Signature
        }) | Out-Null
    }
}

# ---------- 输出 ----------
if ($Json) {
    [pscustomobject]@{
        scanned = $scanned
        skipped = $skipped
        fileViolations = $fileViolations
        functionViolations = $funcViolations
        thresholds = @{ maxFileLines = $MaxFileLines; maxFuncLines = $MaxFuncLines }
    } | ConvertTo-Json -Depth 5
} else {
    Write-Host ""
    Write-Host ("扫描 {0} 个文件（豁免 {1}），阈值：文件 {2} 行 / 函数 {3} 行" -f $scanned, $skipped, $MaxFileLines, $MaxFuncLines) -ForegroundColor Cyan

    if ($fileViolations.Count -eq 0) {
        Write-Host "文件长度：全部通过" -ForegroundColor Green
    } else {
        Write-Host ("文件长度：{0} 个超限" -f $fileViolations.Count) -ForegroundColor Yellow
        $fileViolations | Sort-Object EffectiveLines -Descending | Select-Object -First $Top |
            Format-Table @{n = '有效行'; e = { $_.EffectiveLines } },
                         @{n = '原始行'; e = { $_.RawLines } },
                         @{n = '超出'; e = { $_.Over } },
                         @{n = '文件'; e = { $_.File } } -AutoSize | Out-String -Width 200 | Write-Host
    }

    if ($funcViolations.Count -eq 0) {
        Write-Host "函数长度：全部通过" -ForegroundColor Green
    } else {
        Write-Host ("函数长度：{0} 个超限" -f $funcViolations.Count) -ForegroundColor Yellow
        $funcViolations | Sort-Object Lines -Descending | Select-Object -First $Top |
            Format-Table @{n = '行数'; e = { $_.Lines } },
                         @{n = '起始行'; e = { $_.Line } },
                         @{n = '签名'; e = { $_.Signature } },
                         @{n = '文件'; e = { $_.File } } -AutoSize | Out-String -Width 220 | Write-Host
    }
    Write-Host ""
}

if (($fileViolations.Count + $funcViolations.Count) -gt 0 -and -not $NoFail) { exit 1 }
