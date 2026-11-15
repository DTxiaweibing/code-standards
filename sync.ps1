#Requires -Version 5.1
<#
.SYNOPSIS
    把 D:\standards 的真源分发到各个 agent 的挂载点。

.DESCRIPTION
    1) skill  -> ~/.agents/skills/code-standards        （DSH/Hermes 全局技能，自动发现）
    2) 规则   -> ~/.config/opencode/AGENTS.md           （OpenCode 全局规则，标记块合并）
    3) 规则   -> ~/.cursor/rules/code-standards.mdc     （Cursor 全局规则，alwaysApply）
    4) hooks  -> git 全局 core.hooksPath               （pre-commit 规模门禁）
    5) 可选   -> <Project>\AGENTS.md                    （项目级短 stub，标记块合并）

    标记块合并：只替换 <!-- code-standards:begin --> 与 <!-- code-standards:end --> 之间的内容，
    文件其余部分原样保留。

.EXAMPLE
    pwsh D:\standards\sync.ps1
    pwsh D:\standards\sync.ps1 -Project D:\mixcalc-lab
#>
[CmdletBinding()]
param(
    [string]$Source = $PSScriptRoot,
    [string]$Project,
    [switch]$SkipCursor
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$begin = '<!-- code-standards:begin -->'
$end = '<!-- code-standards:end -->'

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
    if ($current -match $pattern) {
        $updated = [regex]::Replace($current, $pattern, { param($m) $Block })
        Write-TextFile -FilePath $FilePath -Text $updated
        return "updated"
    }
    Write-TextFile -FilePath $FilePath -Text ($current.TrimEnd() + "`n`n" + $Block + "`n")
    return "appended"
}

# ---------- 1. skill（skill\ 下所有子目录，逐个镜像到全局技能目录）----------
$skillRoot = Join-Path $Source "skill"
if (-not (Test-Path -LiteralPath $skillRoot)) { throw "找不到源目录: $skillRoot" }

$syncedSkills = @()
foreach ($dir in (Get-ChildItem -LiteralPath $skillRoot -Directory)) {
    if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName "SKILL.md"))) {
        Write-Host ("  跳过（没有 SKILL.md）: {0}" -f $dir.Name) -ForegroundColor DarkYellow
        continue
    }
    $dst = Join-Path $env:USERPROFILE (".agents\skills\" + $dir.Name)
    $rc = (robocopy $dir.FullName $dst /MIR /NFL /NDL /NJH /NJS /NP) 2>&1
    if ($LASTEXITCODE -ge 8) { throw ("robocopy 失败（{0}）: {1} -> {2}`n{3}" -f $LASTEXITCODE, $dir.Name, $dst, $rc) }
    $syncedSkills += $dir.Name
}
if ($syncedSkills.Count -eq 0) { throw "skill\ 下没有可同步的技能目录" }

# ---------- 2. OpenCode 全局规则 ----------
$coreBlock = @'
<!-- code-standards:begin -->
## 代码规范（全局，强制）

完整规范：`~/.agents/skills/code-standards/SKILL.md`。真源目录：`D:\standards`；改完规范执行 `pwsh D:\standards\sync.ps1` 重新分发。以下为必须遵守的红线：

- **R2 函数 ≤ 50 行**（有效代码行，不含空行/纯注释）；超出按“提取私有方法 → 抽参数对象 → 抽策略”拆。
- **R3 文件 ≤ 500 行**；存量文件不强制重写，但改动时不得净增长；新功能写新文件。
- **R4 一模块一目录**，目录内单一入口（index.ts / __init__.py / 包内唯一 public 类）；禁止跨模块深层 import。
- **R6 不吞异常**：禁止空 catch、禁止 catch 后继续跑；错误在边界转换，日志只打一次。
- **R7 依赖方向**：UI → 应用 → 领域 → 基础设施，领域层不反向依赖框架。
- **R10 豁免**：仅一次性交付物 / 生成代码 / 测试 / 数据表 / 存量文件 / 声明式 UI / 技能示例；需在文件首行写 `standards-exempt: <具体理由>`，一个文件一条。

优先级：项目根 `AGENTS.md` > 本规范 > 技能自带模板。
提交前跑 `~/.agents/skills/code-standards/scripts/check-limits.ps1`。
<!-- code-standards:end -->
'@

$opencodeRules = Join-Path $env:USERPROFILE ".config\opencode\AGENTS.md"
$r1 = Set-MarkedBlock -FilePath $opencodeRules -Block $coreBlock

# ---------- 3. Cursor 全局规则 ----------
$r2 = "skipped"
if (-not $SkipCursor) {
    $cursorFile = Join-Path $env:USERPROFILE ".cursor\rules\code-standards.mdc"
    $mdc = @'
---
description: Code size and structure standards (functions ≤50 lines, files ≤500 lines, one module per folder)
globs: ["**/*"]
alwaysApply: true
---

# Code Standards（全局）

完整版：`~/.agents/skills/code-standards/SKILL.md`。真源：`D:\standards`（改完跑 `sync.ps1`）。

- R2 函数/方法 ≤ 50 行有效代码；超出按“提取私有方法 → 抽参数对象 → 抽策略”拆。
- R3 文件 ≤ 500 行；存量文件改动时不得净增长。
- R4 一个模块一个目录，单一入口；禁止跨模块深层 import。
- R6 禁止空 catch / 吞异常；错误在边界转换。
- R7 依赖方向 UI → 应用 → 领域 → 基础设施。
- R10 豁免仅限：一次性交付物、生成代码、测试、数据表、存量文件、声明式 UI、技能示例；需在首行注明 `standards-exempt: <理由>`。

优先级：项目 AGENTS.md > 本规则 > 技能模板。
'@
    Write-TextFile -FilePath $cursorFile -Text $mdc
    $r2 = "written"
}

# ---------- 4. git 全局 pre-commit 门禁 ----------
$rHooks = "skipped"
$hooksDir = Join-Path $Source "hooks"
if (-not $SkipHooks -and (Test-Path -LiteralPath (Join-Path $hooksDir "pre-commit"))) {
    & git config --global core.hooksPath $hooksDir
    if ($LASTEXITCODE -ne 0) { throw "设置 git core.hooksPath 失败" }
    $rHooks = "core.hooksPath=$hooksDir"
} elseif (-not (Test-Path -LiteralPath (Join-Path $hooksDir "pre-commit"))) {
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

- 提交前：`pwsh ~/.agents/skills/code-standards/scripts/check-limits.ps1 -Path . -NoFail`
- 本项目特有约定写在下面（如构建命令、目录约定）：

<!-- 在这里补充项目专属规则 -->

<!-- code-standards:end -->
'@
    $r3 = Set-MarkedBlock -FilePath $projAgents -Block $stub
}

# ---------- 汇总 ----------
Write-Host ""
Write-Host "同步完成" -ForegroundColor Green
Write-Host ("  skill      -> {0}  ({1})" -f (Join-Path $env:USERPROFILE ".agents\skills"), ($syncedSkills -join ", "))
Write-Host ("  opencode   -> {0}  ({1})" -f $opencodeRules, $r1)
Write-Host ("  cursor     -> {0}  ({1})" -f (Join-Path $env:USERPROFILE ".cursor\rules\code-standards.mdc"), $r2)
Write-Host ("  git hooks  -> {0}  ({1})" -f $hooksDir, $rHooks)
if ($Project) { Write-Host ("  project    -> {0}  ({1})" -f (Join-Path $Project "AGENTS.md"), $r3) }
Write-Host ""
Write-Host "验证：重启会话后，skill 应出现在技能列表中；或直接读 SKILL.md。" -ForegroundColor DarkGray
