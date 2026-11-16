#Requires -Version 5.1
<#
.SYNOPSIS
    文档一致性检查：防止断链、规则编号漂移、硬编码本机路径。

.DESCRIPTION
    CI 里与 run-tests.ps1 一起跑。检查项：
      1. 所有 Markdown 里的相对 .md 链接都指向真实文件
      2. SKILL.md 覆盖 R0–R14 全部规则编号
      3. 仓库内不再出现硬编码的 D 盘真源路径
      4. README 提到 R12 / R13 / R14

.EXAMPLE
    pwsh ./tests/check-docs.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..'))
$skillDir = [System.IO.Path]::Combine($repo, 'skill', 'code-standards')
$skillMd = [System.IO.Path]::Combine($skillDir, 'SKILL.md')
$readme = [System.IO.Path]::Combine($repo, 'README.md')

$script:failed = 0
function Fail {
    param([string]$Message)
    $script:failed++
    Write-Host "  FAIL  $Message" -ForegroundColor Red
}

Write-Host "docs consistency" -ForegroundColor Cyan
Write-Host ""

# 1. 相对链接
$mdFiles = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Filter *.md |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($file in $mdFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    foreach ($m in [regex]::Matches($text, '\]\(([^)\s#]+?\.md)(#[^)]*)?\)')) {
        $rel = $m.Groups[1].Value
        if ($rel -match '^[a-z]+://') { continue }
        $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($file.DirectoryName, $rel))
        if (-not (Test-Path -LiteralPath $target)) {
            Fail ("{0} -> {1}（不存在）" -f $file.Name, $rel)
        }
    }
}
Write-Host ("- 检查了 {0} 个 Markdown 文件" -f $mdFiles.Count)

# 1b. 反引号 / 表格里的 .md 路径（不要求是标准链接语法）
foreach ($file in $mdFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    foreach ($m in [regex]::Matches($text, '`([A-Za-z0-9_.\-/]+\.md)`')) {
        $rel = $m.Groups[1].Value
        if ($rel -match '^[a-z]+://') { continue }
        if ($rel -notmatch '/') { continue }             # AGENTS.md 等运行时文件
        if ($rel.StartsWith('.review/')) { continue }    # 运行时生成的台账
        if ($rel.StartsWith('.codebuddy/')) { continue } # 运行时生成的项目文件
        $candidates = @(
            [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($file.DirectoryName, $rel)),
            [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo, $rel)),
            [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($skillDir, $rel))
        )
        $found = $false
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) { $found = $true; break }
        }
        if (-not $found) { Fail ("{0} 引用了不存在的路径 {1}" -f $file.Name, $rel) }
    }
}
Write-Host "- 检查反引号中的 .md 路径"

# 2. R0–R14 编号
$skillText = [System.IO.File]::ReadAllText($skillMd)
for ($n = 0; $n -le 14; $n++) {
    if ($skillText -notmatch "\bR$n\b") { Fail "SKILL.md 缺少规则编号 R$n" }
}
Write-Host "- 检查 R0–R14 编号"

# 3. 硬编码真源路径（用拼接避免本文件自己命中）
$badPath = 'D:' + '\standards'
$hits = @(Get-ChildItem -LiteralPath $repo -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Extension -in @('.md', '.ps1', '.sh', '.mjs', '.xml', '.toml', '.yml', '.yaml') } |
    Select-String -SimpleMatch -Pattern $badPath)
if ($hits.Count -gt 0) {
    foreach ($h in $hits) { Fail ("硬编码路径：{0}:{1}" -f $h.Path, $h.LineNumber) }
} else {
    Write-Host "- 无硬编码 D 盘真源路径"
}

# 4. README 覆盖新增规则
$readmeText = [System.IO.File]::ReadAllText($readme)
foreach ($rule in @('R12', 'R13', 'R14')) {
    if ($readmeText -notmatch "\b$rule\b") { Fail "README.md 未提到 $rule" }
}
Write-Host "- 检查 README 新增规则"

Write-Host ""
if ($script:failed -gt 0) {
    Write-Host ("文档一致性检查失败：{0} 项。" -f $script:failed) -ForegroundColor Red
    exit 1
}
Write-Host "文档一致性检查通过。" -ForegroundColor Green
exit 0
