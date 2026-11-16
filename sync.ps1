#Requires -Version 5.1
<#
.SYNOPSIS
    把 standards 真源分发到各个 agent 的挂载点（Windows / Linux / macOS 通用）。

.DESCRIPTION
    1) skill  -> ~/.agents/skills/<技能名>              （DSH/Hermes 全局技能，自动发现）
   1b) skill  -> ~/.workbuddy/skills/<技能名>           （WorkBuddy 全局技能，自动发现）
    2) 规则   -> ~/.config/opencode/AGENTS.md           （OpenCode 全局规则，标记块合并；仅在已安装时写入）
    3) 规则   -> ~/.cursor/rules/code-standards.mdc     （Cursor 全局规则；仅在已安装时写入）
    4) hooks  -> git 全局 core.hooksPath               （pre-commit 规模门禁）
    5) 可选   -> <Project>\AGENTS.md                    （项目级短 stub，标记块合并）

    标记块合并：只替换 <!-- code-standards:begin --> 与 <!-- code-standards:end --> 之间的内容，
    文件其余部分原样保留。

    注意：本文件必须存成 UTF-8 with BOM，Windows PowerShell 5.1 才能正确解析中文。
    PowerShell 7 无此限制。

.EXAMPLE
    pwsh ./sync.ps1
    pwsh ./sync.ps1 -Project /path/to/proj
    pwsh ./sync.ps1 -SkipHooks
#>
[CmdletBinding()]
param(
    [string]$Source = $PSScriptRoot,
    [string]$Project,
    [switch]$SkipCursor,
    [switch]$SkipHooks
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$begin = '<!-- code-standards:begin -->'
$end = '<!-- code-standards:end -->'

# USERPROFILE 是 Windows 专有；Linux/macOS 用 HOME
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
if (-not $HomeDir) { throw "无法确定用户主目录（USERPROFILE / HOME 均为空）" }

function Write-TextFile {
    param([string]$FilePath, [string]$Text)
    $dir = Split-Path -Parent $FilePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($FilePath, $Text, $utf8NoBom)
}

function Set-MarkedBlock {
    param([string]$FilePath, [string]$Block)
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-TextFile -FilePath $FilePath -Text ($Block + "`n")
        return "created"
    }
    $current = [System.IO.File]::ReadAllText($FilePath)
    $pattern = [regex]::Escape($begin) + '[\s\S]*?' + [regex]::Escape($end)
    $match = [regex]::Match($current, $pattern)
    if ($match.Success) {
        # 用子串拼接而不是 MatchEvaluator：PowerShell 5.1 对 scriptblock 委托支持不一致
        $updated = $current.Substring(0, $match.Index) + $Block + $current.Substring($match.Index + $match.Length)
        Write-TextFile -FilePath $FilePath -Text $updated
        return "updated"
    }
    Write-TextFile -FilePath $FilePath -Text ($current.TrimEnd() + "`n`n" + $Block + "`n")
    return "appended"
}

# 镜像复制：不再依赖 robocopy（Windows 专有），保持 /MIR 语义（目标端多余文件会被删除）
function Sync-SkillTree {
    param([string]$SkillDir, [string]$Root, [string]$Name)
    $dst = Join-Path $Root $Name
    if (-not (Test-Path -LiteralPath $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }
    $base = $SkillDir -replace '[\\/]+$', ''
    $dstBase = $dst -replace '[\\/]+$', ''

    foreach ($file in (Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
        $rel = $file.FullName.Substring($base.Length).TrimStart([char[]]('\', '/'))
        $target = Join-Path $dstBase $rel
        $targetDir = Split-Path -Parent $target
        if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }

    # 删除目标端多出来的文件（源端已删除）
    foreach ($file in (Get-ChildItem -LiteralPath $dstBase -Recurse -File -Force)) {
        $rel = $file.FullName.Substring($dstBase.Length).TrimStart([char[]]('\', '/'))
        if (-not (Test-Path -LiteralPath (Join-Path $base $rel))) {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }
}

# ---------- 1. skill（skill\ 下所有子目录，逐个镜像到全局技能目录）----------
$skillRoot = Join-Path $Source "skill"
if (-not (Test-Path -LiteralPath $skillRoot)) { throw "找不到源目录: $skillRoot" }

$skills = @(Get-ChildItem -LiteralPath $skillRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") })
if ($skills.Count -eq 0) { throw "skill\ 下没有可同步的技能目录（缺 SKILL.md）" }

$skillTargets = @(
    [pscustomobject]@{ Label = "agents";    Root = (Join-Path (Join-Path $HomeDir ".agents") "skills") },
    [pscustomobject]@{ Label = "workbuddy"; Root = (Join-Path (Join-Path $HomeDir ".workbuddy") "skills") }
)

$skillReports = @()
foreach ($target in $skillTargets) {
    $parent = Split-Path -Parent $target.Root
    if (-not (Test-Path -LiteralPath $parent)) {
        $skillReports += [pscustomobject]@{ Label = $target.Label; Text = ("未安装（没有 {0}）" -f $parent) }
        continue
    }
    $count = 0
    foreach ($dir in $skills) {
        Sync-SkillTree -SkillDir $dir.FullName -Root $target.Root -Name $dir.Name
        $count++
    }
    $skillReports += [pscustomobject]@{ Label = $target.Label; Text = ("{0} 个技能" -f $count) }
}

# ---------- 2. OpenCode 全局规则（仅在已安装时写入）----------
$opencodeRoot = Join-Path (Join-Path $HomeDir ".config") "opencode"
$opencodeRules = Join-Path $opencodeRoot "AGENTS.md"
$r1 = "skipped（未安装 OpenCode）"
if (Test-Path -LiteralPath $opencodeRoot) {
    $coreBlock = @'
<!-- code-standards:begin -->
## 代码规范（全局，强制）

完整规范：`~/.agents/skills/code-standards/SKILL.md`。真源目录：`__STANDARDS_ROOT__`；改完规范执行 `pwsh __STANDARDS_ROOT__/sync.ps1` 重新分发。以下为必须遵守的红线：

- **R2 函数 ≤ 50 行**（有效代码行，不含空行/纯注释/单独收尾括号）；超出按“提取私有方法 → 抽参数对象 → 抽策略”拆。
- **R3 文件 ≤ 500 行**；存量文件不强制重写，但改动时不得净增长；新功能写新文件。
- **R4 一模块一目录**，目录内单一入口（index.ts / __init__.py / 包内唯一 public 类）；禁止跨模块深层 import。
- **R6 不吞异常**：禁止空 catch、禁止 catch 后继续跑；错误在边界转换，日志只打一次。
- **R7 依赖方向**：UI → 应用 → 领域 → 基础设施，领域层不反向依赖框架。
- **R10 豁免**：仅一次性交付物 / 生成代码 / 测试 / 数据表 / 存量文件 / 声明式 UI / 技能示例；需在文件前 5 行写 `standards-exempt: <具体理由>`，一个文件一条。
- **R12 安全**：密钥不入库；输入在边界校验；新增依赖先查漏洞与许可证。
- **R13 测试**：改逻辑必须带测试；测试与源码同目录；禁止依赖 sleep 的用例。
- **R14 依赖**：lockfile 必须提交；新增依赖需说明理由与许可证。

优先级：项目根 `AGENTS.md` > 本规范 > 技能自带模板；**R12 安全/合规条款不可被项目约定降级**。
提交前跑 `~/.agents/skills/code-standards/scripts/check-limits.ps1`。
<!-- code-standards:end -->
'@
    $coreBlock = $coreBlock.Replace('__STANDARDS_ROOT__', $Source)
    $r1 = Set-MarkedBlock -FilePath $opencodeRules -Block $coreBlock
}

# ---------- 3. Cursor 全局规则（仅在已安装时写入）----------
$r2 = "skipped"
if ($SkipCursor) {
    $r2 = "skipped (-SkipCursor)"
} elseif (Test-Path -LiteralPath (Join-Path $HomeDir ".cursor")) {
    $cursorFile = Join-Path (Join-Path (Join-Path $HomeDir ".cursor") "rules") "code-standards.mdc"
    $mdc = @'
---
description: Code standards (functions <= 50 lines, files <= 500 lines, one module per folder, security/testing/dependency rules)
globs: ["**/*"]
alwaysApply: true
---

# Code Standards（全局）

完整版：`~/.agents/skills/code-standards/SKILL.md`。真源：`__STANDARDS_ROOT__`（改完跑 `sync.ps1`）。

- R2 函数/方法 ≤ 50 行有效代码；超出按“提取私有方法 → 抽参数对象 → 抽策略”拆。
- R3 文件 ≤ 500 行；存量文件改动时不得净增长。
- R4 一个模块一个目录，单一入口；禁止跨模块深层 import。
- R6 禁止空 catch / 吞异常；错误在边界转换。
- R7 依赖方向 UI → 应用 → 领域 → 基础设施。
- R10 豁免仅限：一次性交付物、生成代码、测试、数据表、存量文件、声明式 UI、技能示例；需在前 5 行注明 `standards-exempt: <理由>`。
- R12 密钥不入库；输入边界校验；依赖查漏洞与许可证。
- R13 改逻辑必须带测试。
- R14 lockfile 必须提交。

优先级：项目 AGENTS.md > 本规则 > 技能模板；安全/合规条款不可降级。
'@
    $mdc = $mdc.Replace('__STANDARDS_ROOT__', $Source)
    Write-TextFile -FilePath $cursorFile -Text $mdc
    $r2 = "written"
} else {
    $r2 = "skipped（未安装 Cursor）"
}

# ---------- 4. git 全局 pre-commit 门禁 ----------
$rHooks = "skipped"
$hooksDir = Join-Path $Source "hooks"
if ($SkipHooks) {
    $rHooks = "skipped (-SkipHooks)"
} elseif (Test-Path -LiteralPath (Join-Path $hooksDir "pre-commit")) {
    & git config --global core.hooksPath $hooksDir
    if ($LASTEXITCODE -ne 0) { throw "设置 git core.hooksPath 失败" }
    $rHooks = "core.hooksPath=$hooksDir"
} else {
    $rHooks = "no hooks/pre-commit"
}

# ---------- 5. 项目 stub ----------
$r3 = "skipped"
if ($Project) {
    $projAgents = Join-Path $Project "AGENTS.md"
    $stub = @'
<!-- code-standards:begin -->
## 项目约定

本项目遵循全局代码规范（`~/.agents/skills/code-standards/SKILL.md`）：
函数 ≤ 50 行、文件 ≤ 500 行、一模块一目录、单一入口、禁止跨模块深层 import。
安全（R12）、测试（R13）、依赖（R14）条款不可被本项目降级。

- 提交前：`pwsh __STANDARDS_ROOT__/skill/code-standards/scripts/check-limits.ps1 -Path . -NoFail`
- 本项目特有约定写在下面（如构建命令、目录约定）：

<!-- 在这里补充项目专属规则 -->

<!-- code-standards:end -->
'@
    $stub = $stub.Replace('__STANDARDS_ROOT__', $Source)
    $r3 = Set-MarkedBlock -FilePath $projAgents -Block $stub
}

# ---------- 汇总 ----------
Write-Host ""
Write-Host "同步完成" -ForegroundColor Green
Write-Host ("  skill      -> {0}" -f (($skills | ForEach-Object { $_.Name }) -join ", "))
foreach ($report in $skillReports) {
    Write-Host ("  {0,-10} -> {1}" -f $report.Label, $report.Text)
}
Write-Host ("  opencode   -> {0}  ({1})" -f $opencodeRules, $r1)
Write-Host ("  cursor     -> {0}  ({1})" -f (Join-Path (Join-Path (Join-Path $HomeDir ".cursor") "rules") "code-standards.mdc"), $r2)
Write-Host ("  git hooks  -> {0}  ({1})" -f $hooksDir, $rHooks)
if ($Project) { Write-Host ("  project    -> {0}  ({1})" -f (Join-Path $Project "AGENTS.md"), $r3) }
Write-Host ""
Write-Host "验证：重启会话后，skill 应出现在技能列表中；或直接读 SKILL.md。" -ForegroundColor DarkGray
