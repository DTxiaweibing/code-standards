#Requires -Version 5.1
<#
.SYNOPSIS
    跨语言代码规模检查：文件 ≤ MaxFileLines、函数 ≤ MaxFuncLines（默认 500 / 50）。

.DESCRIPTION
    对应规范 R2（函数 ≤50 行）与 R3（文件 ≤500 行）。
    语言：TS/JS/Java/Kotlin/C/C++/C#/Go/Rust 走大括号匹配；Python 走缩进块。
    只做规模审计，不做风格检查（风格交给 eslint/checkstyle/clang-tidy/ruff）。
    豁免：文件前 5 行内出现 standards-exempt 的文件直接跳过
          （前 5 行是为了让 shebang / PEP 263 编码声明 / #Requires 能占第一行）。

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

function New-LexState {
    # 跨行状态：块注释 / 逐字串 / 多行串（模板串、C++ 原生串、Python 三引号）
    [pscustomobject]@{
        InBlockComment = $false
        Quote          = [char]0
        Verbatim       = $false
        Terminator     = ''
    }
}

function Get-StringStart {
    # 判断 $Rest 开头是不是“会跨行的字符串”，返回它的种类、终止符和起始长度
    param([string]$Rest, [string]$Extension)
    if ($Rest.Length -eq 0) { return $null }
    if ($Extension -eq '.py') {
        if ($Rest.StartsWith('"""') -or $Rest.StartsWith("'''")) {
            return [pscustomobject]@{ Kind = 'multi'; Terminator = $Rest.Substring(0, 3); Length = 3 }
        }
        return $null
    }
    if ($Rest.StartsWith('R"')) {
        # C++11 原生串：R"delim( ... )delim"
        $m = [regex]::Match($Rest, '^R"(?<d>[^()\\\s]{0,16})\(')
        if ($m.Success) {
            return [pscustomobject]@{ Kind = 'multi'; Terminator = ')' + $m.Groups['d'].Value + '"'; Length = $m.Length }
        }
    }
    if ($Rest.StartsWith('@"')) { return [pscustomobject]@{ Kind = 'verbatim'; Terminator = ''; Length = 2 } }
    if ($Rest[0] -eq '`') { return [pscustomobject]@{ Kind = 'multi'; Terminator = '`'; Length = 1 } }
    return $null
}

function Get-FunctionName {
    # 从清洗后的签名里取函数名，作为 pre-commit 判定“是否新增超限函数”的稳定键
    param([string]$Text)
    $skip = @('async', 'function', 'if', 'for', 'foreach', 'while', 'switch', 'catch',
        'new', 'return', 'await', 'typeof', 'sizeof', 'using', 'lock', 'synchronized')
    foreach ($m in [regex]::Matches($Text, '([A-Za-z_$][\w$]*)\s*\(')) {
        $name = $m.Groups[1].Value
        if ($skip -contains $name) { continue }
        return $name
    }
    $m = [regex]::Match($Text, '(?:const|let|var|val)\s+([\w$]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return '<anonymous>'
}

function Get-StateAdvance {
    # 当前字符已被某个跨行状态（多行串 / 逐字串 / 块注释 / 普通引号串）消费时返回下一个下标，否则 -1
    param([string]$Line, [int]$Index, $State)
    $c = $Line[$Index]
    $rest = $Line.Substring($Index)

    if ($State.Terminator) {
        if ($c -eq '\' -and $State.Terminator -eq '`') { return $Index + 2 }
        if ($rest.StartsWith($State.Terminator)) {
            $len = $State.Terminator.Length
            $State.Terminator = ''
            return $Index + $len
        }
        return $Index + 1
    }
    if ($State.Verbatim) {
        if ($c -ne '"') { return $Index + 1 }
        if (($Index + 1) -lt $Line.Length -and $Line[$Index + 1] -eq '"') { return $Index + 2 }
        $State.Verbatim = $false
        return $Index + 1
    }
    if ($State.InBlockComment) {
        if ($c -eq '*' -and ($Index + 1) -lt $Line.Length -and $Line[$Index + 1] -eq '/') {
            $State.InBlockComment = $false
            return $Index + 2
        }
        return $Index + 1
    }
    if ($State.Quote -ne [char]0) {
        if ($c -eq '\') { return $Index + 2 }
        if ($c -eq $State.Quote) { $State.Quote = [char]0 }
        return $Index + 1
    }
    return -1
}

function Get-CleanedLine {
    # 返回“只剩代码”的行：注释、字符串内容全部剔除，花括号计数才不会被子串带偏
    param(
        [string]$Line,
        $State,
        [string]$Extension
    )
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Line.Length) {
        $advance = Get-StateAdvance -Line $Line -Index $i -State $State
        if ($advance -ge 0) { $i = $advance; continue }

        $c = $Line[$i]
        $start = Get-StringStart -Rest $Line.Substring($i) -Extension $Extension
        if ($start) {
            if ($start.Kind -eq 'verbatim') { $State.Verbatim = $true }
            elseif ($start.Terminator.Length -gt 1 -or $start.Terminator -eq '`') { $State.Terminator = $start.Terminator }
            else { $State.Quote = [char]$start.Terminator[0] }
            $i += $start.Length
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $Line.Length) {
            if ($Line[$i + 1] -eq '/') { break }
            if ($Line[$i + 1] -eq '*') { $State.InBlockComment = $true; $i += 2; continue }
        }
        if ($c -eq '"' -or $c -eq "'") { $State.Quote = $c; $i++; continue }
        [void]$sb.Append($c)
        $i++
    }
    # 普通引号串不跨行，行尾必须复位；多行串和块注释保持状态到下一行
    if ($State.Quote -ne [char]0) { $State.Quote = [char]0 }
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

function Get-CommentPrefixes {
    param([string]$Extension)
    # Python 用 #；C/C++ 的 # 是预处理指令（算代码），不能当注释
    # 块注释不在这里给前缀：单看行首的 * 会把 `*p = 1;` 这类解引用行误判成注释
    if ($Extension -eq '.py') { return @('#') }
    return @('//')
}

function Get-EffectiveLineCount {
    param(
        [string[]]$Lines,
        [int]$Start,
        [int]$End,
        [string[]]$CommentPrefixes = @('//')
    )
    $n = 0
    $inBlock = $false
    for ($i = $Start; $i -le $End -and $i -le $Lines.Count; $i++) {
        $l = $Lines[$i - 1].Trim()
        if ($inBlock) {
            $close = $l.IndexOf('*/')
            if ($close -lt 0) { continue }
            $l = $l.Substring($close + 2).Trim()
            $inBlock = $false
        }
        if ($l -eq '') { continue }
        if ($l.StartsWith('#!')) { continue }
        if ($l.StartsWith('/*')) {
            $close = $l.IndexOf('*/')
            if ($close -lt 0) { $inBlock = $true; continue }
            $l = $l.Substring($close + 2).Trim()
            if ($l -eq '') { continue }
        }
        $isComment = $false
        foreach ($prefix in $CommentPrefixes) {
            if ($l.StartsWith($prefix)) { $isComment = $true; break }
        }
        if ($isComment) { continue }
        if ($l -match '^[\}\)\];,]+$') { continue }
        $n++
    }
    return $n
}

function Get-DisplaySignature {
    # 表格里一行放得下的签名
    param([string]$Text)
    $sig = ($Text.Trim() -replace '\s+', ' ')
    if ($sig.Length -gt 60) { return $sig.Substring(0, 60) + '…' }
    return $sig
}

function Get-BraceFunctions {
    param([string[]]$Lines, [int]$MaxFunc, [string]$Extension, [string[]]$CommentPrefixes = @('//'))
    $results = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.List[object]
    $state = New-LexState
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $clean = Get-CleanedLine -Line $Lines[$i] -State $state -Extension $Extension
        $opens = ([regex]::Matches($clean, '\{')).Count
        $closes = ([regex]::Matches($clean, '\}')).Count
        for ($k = 0; $k -lt $opens; $k++) {
            $stack.Add(@{ Line = ($i + 1); Text = $Lines[$i]; Clean = $clean }) | Out-Null
        }
        for ($k = 0; $k -lt $closes; $k++) {
            if ($stack.Count -eq 0) { continue }
            $frame = $stack[$stack.Count - 1]
            $stack.RemoveAt($stack.Count - 1)
            # 用清洗后的行判断“是不是函数头”：字符串里的 ) { 不能算
            if (-not (Test-IsFunctionHead -Text $frame.Clean)) { continue }
            $eff = Get-EffectiveLineCount -Lines $Lines -Start $frame.Line -End ($i + 1) -CommentPrefixes $CommentPrefixes
            if ($eff -le $MaxFunc) { continue }
            $results.Add([pscustomobject]@{
                    Line      = $frame.Line
                    Lines     = $eff
                    Name      = (Get-FunctionName -Text $frame.Clean)
                    Signature = (Get-DisplaySignature -Text $frame.Text)
                }) | Out-Null
        }
    }
    return $results
}

function Get-PythonFunctions {
    param([string[]]$Lines, [int]$MaxFunc, [string[]]$CommentPrefixes = @('#'))
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
        $eff = Get-EffectiveLineCount -Lines $Lines -Start ($i + 1) -End $end -CommentPrefixes $CommentPrefixes
        if ($eff -gt $MaxFunc) {
            $results.Add([pscustomobject]@{
                    Line = ($i + 1); Lines = $eff; Name = $name; Signature = "def $name(...)"
                }) | Out-Null
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

    # 豁免声明允许出现在前 5 行：兼容 shebang / PEP 263 / #Requires
    $isExempt = $false
    $headCount = [Math]::Min(5, $lines.Count)
    for ($h = 0; $h -lt $headCount; $h++) {
        if ($lines[$h] -match 'standards-exempt') { $isExempt = $true; break }
    }
    if ($isExempt) { $skipped++; continue }

    $ext = $f.Extension.ToLower()
    $commentPrefixes = Get-CommentPrefixes -Extension $ext

    $scanned++
    $raw = $lines.Count
    $eff = Get-EffectiveLineCount -Lines $lines -Start 1 -End $raw -CommentPrefixes $commentPrefixes
    if ($eff -gt $MaxFileLines) {
        $fileViolations.Add([pscustomobject]@{
            File = $f.FullName; RawLines = $raw; EffectiveLines = $eff; Over = $eff - $MaxFileLines
        }) | Out-Null
    }

    $funcs = @()
    if ($ext -eq '.py') {
        $funcs = Get-PythonFunctions -Lines $lines -MaxFunc $MaxFuncLines -CommentPrefixes $commentPrefixes
    } else {
        $funcs = Get-BraceFunctions -Lines $lines -MaxFunc $MaxFuncLines -Extension $ext -CommentPrefixes $commentPrefixes
    }
    foreach ($fn in $funcs) {
        $funcViolations.Add([pscustomobject]@{
            File = $f.FullName; Line = $fn.Line; Lines = $fn.Lines; Name = $fn.Name; Signature = $fn.Signature
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
