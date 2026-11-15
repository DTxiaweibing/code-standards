# standards — 个人代码规范（真源）

一套可执行的代码规范：**函数 ≤ 50 行、文件 ≤ 500 行、一模块一目录**。
文本约束给 agent 看，linter 给机器看，两边都有才算数。

## 目录

```
standards/
├── skill/
│   ├── code-standards/           # 代码规模/结构规范（R0–R10）
│   │   ├── SKILL.md
│   │   ├── references/           # 语言细则 + 豁免清单（按需加载）
│   │   └── scripts/check-limits.ps1
│   ├── harmony-arkui-input-focus/  # 鸿蒙输入框/键盘/焦点实战经验
│   │   └── SKILL.md
│   └── android-custom-table/       # 安卓大表格自绘 + 共用编辑框 + 惯性解析
│       └── SKILL.md
├── linters/                      # eslint / checkstyle / clang-tidy / ruff / editorconfig
├── hooks/                        # 全局 git pre-commit 门禁（只查本次提交的文件）
│   ├── pre-commit                # sh 入口（找 pwsh / powershell）
│   └── pre-commit.ps1            # 新文件超限直接拦；存量文件只拦新增超限
├── sync.ps1                      # 分发到各 agent 挂载点 + 安装 git 全局钩子
└── README.md
```

> `sync.ps1` 会遍历 `skill\` 下的**所有子目录**（只要有 `SKILL.md`），逐个镜像到
> `~\.agents\skills\<名字>\`。新增技能只要建个目录放 `SKILL.md`，再跑一次同步即可。

## 安装 / 更新

```powershell
pwsh D:\standards\sync.ps1                    # 分发到 DSH + OpenCode + Cursor + git 全局钩子
pwsh D:\standards\sync.ps1 -Project D:\proj   # 额外给某个项目放 AGENTS.md stub
pwsh D:\standards\sync.ps1 -SkipHooks         # 不安装/不覆盖 git core.hooksPath
```

改了真源就重跑一次；`sync.ps1` 是幂等的，重复执行无副作用。

> ⚠️ `sync.ps1` 自身必须存成 **UTF-8 with BOM**：Windows PowerShell 5.1 读无 BOM 的
> UTF-8 会按 GBK 解析，中文字符串直接语法报错。用编辑器保存时注意别去掉 BOM。

## 挂载点

| Agent | 路径 | 机制 |
|---|---|---|
| DSH / Hermes | `~\.agents\skills\<技能名>\` | 全局技能，自动发现（`skill\` 下所有目录） |
| OpenCode | `~\.config\opencode\AGENTS.md` | 全局规则，标记块合并 |
| Cursor | `~\.cursor\rules\code-standards.mdc` | `alwaysApply: true` |
| 任意项目 | `<repo>\AGENTS.md` | 项目级 stub（2k 字符内） |
| 任意 git 仓库 | `~\.config\git\config` → `core.hooksPath` | 全局 pre-commit（`D:\standards\hooks`） |

> 为什么不放 `~\AGENTS.md`：Hermes/DSH 的上下文文件是 **cwd-only、first-match-wins**，
> home 级 AGENTS.md 不会跨项目生效；跨项目规则必须走 skill。

## 在项目里启用

```powershell
# 1. 规模检查（零依赖）
pwsh D:\standards\skill\code-standards\scripts\check-limits.ps1 -Path . -NoFail

# 2. 按语言挂 linter
#    TS/JS  : 复制 linters/eslint.config.mjs 到项目根
#    Java   : checkstyle -c D:\standards\linters\checkstyle.xml src/
#    C/C++  : clang-tidy --config-file=D:\standards\linters\.clang-tidy
#    Python : ruff check --config D:\standards\linters\ruff.toml .
```

建议在 `pre-commit` 或 CI 里跑第 1 条，否则规则会随“这次赶时间”退化。
`sync.ps1` 会把 git 全局 `core.hooksPath` 指到 `hooks\`，所以本机所有仓库默认已有这道门禁。

## 提交门禁（pre-commit）

`hooks\pre-commit.ps1` 只检查**本次提交涉及的文件**，不扫全仓，避免存量老项目直接不可提交：

| 场景 | 结果 |
|---|---|
| 新文件 > 500 行，或新文件里有 > 50 行的函数 | 拦截 |
| 存量文件本次越过 500 行 | 拦截 |
| 已超限的存量文件继续变长（R3 净增长） | 拦截 |
| 存量文件里新增一个 > 50 行的函数 | 拦截 |
| 存量文件缩短 / 持平，或本来就超限但没变长 | 放行 |
| 首行写了 `standards-exempt` | 放行 |

跳过本次检查：`git commit --no-verify`。
仓库若自己用 husky 等工具覆盖了 `core.hooksPath`，以该仓库配置为准，全局门禁不生效。

## 豁免

| 类别 | 覆盖 | 说明 |
|---|---|---|
| E1 一次性交付物 | R2 R3 R4 | 单文件 HTML demo、图表、原型、渲染脚本 |
| E2 生成代码 | R2 R3 | protobuf、ORM migration、资源索引 |
| E3 测试 | R2 | 用例可以长，文件行数仍建议遵守 |
| E4 数据/常量表 | R2 R3 | 衡量的是数据条数 |
| E5 存量文件 | R3 | 不强制重写，改动不得净增长 |
| E6 声明式 UI | R2 | ArkUI build()/JSX 按抽子组件后折算 |
| E7 技能示例 | R2 R3 R4 | 教学代码，落地时按规范重写 |

声明方式：文件首行 `// standards-exempt: E1 单文件演示页`（Python 用 `#`）。永不豁免：新生产代码套 E1、被改文件净增长、空 catch、跨模块深层 import。

## 与现有技能的关系

- `code-metrics-analysis`（Function < 50）、`static-code-analysis`（>50 行告警）与本规范**同向**，不冲突。
- 强制单文件产出的技能（`p5js`、`sketch`、`hallmark`、`architecture-diagram`、`manim-video` 等）落在 E1/E7 豁免里。
- 优先级：项目 `AGENTS.md` > 本规范 > 技能模板。

## 更新流程

1. 改 `skill/code-standards/` 下的文件
2. `git commit`（建议把这个目录纳入版本管理）
3. `pwsh sync.ps1` 分发（技能 + 全局规则 + Cursor + git 钩子）
4. 重启 agent 会话让 skill 重新加载

## 审查节奏（R11）

| 层 | 触发 | 做什么 |
|---|---|---|
| L0 | 每次改完文件 | `check-limits.ps1`（pre-commit 自动跑，秒级） |
| L1 | 一个可评审单元（diff ≤ 400 行） | `review-check.ps1` + 自查清单 |
| L2 | 每模块 / 合并前 | 另起 subagent 独立评审（只给 diff + 验收标准） |
| L3 | 上线前 | 全量审计：安全、依赖、文档、性能 |

```powershell
pwsh D:\standards\skill\code-standards\scripts\review-check.ps1 -Path . -Ledger .review/ledger.md -Append
```

台账规则、自查清单、级别定义见 `skill/code-standards/references/review-gate.md`。
