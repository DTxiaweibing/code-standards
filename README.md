# standards — 个人代码规范（真源）

一套可执行的代码规范：**函数 ≤ 50 行、文件 ≤ 500 行、一模块一目录**，
外加安全、测试、依赖三条不可降级的底线。
文本约束给 agent 看，linter 给机器看，CI 兜底，三边都有才算数。

## 目录

```
standards/
├── skill/
│   ├── code-standards/              # 代码规范（R0–R14）
│   │   ├── SKILL.md
│   │   ├── references/              # 语言细则 + 安全/测试/依赖 + 豁免 + 审查
│   │   └── scripts/
│   │       ├── check-limits.ps1     # 规模检查（R2/R3）
│   │       └── review-check.ps1     # 审查扫描 + 台账
│   ├── harmony-arkui-input-focus/   # 鸿蒙输入框/键盘/焦点实战经验
│   └── android-custom-table/        # 安卓大表格自绘 + 共用编辑框
├── linters/                         # eslint(+TS overlay) / checkstyle / clang-tidy / ruff / editorconfig
├── hooks/                           # 全局 git pre-commit 门禁（只查本次提交的文件）
│   ├── pre-commit                   # sh 入口（找 pwsh / powershell，找不到则拒绝提交）
│   └── pre-commit.ps1               # 规模检查 + 密钥扫描
├── tests/                           # check-limits 的 golden 测试 + 文档一致性检查
├── .github/                         # CI + PR 模板
├── sync.ps1                         # 分发到各 agent 挂载点 + 安装 git 全局钩子
├── LICENSE / SECURITY.md / CONTRIBUTING.md / CHANGELOG.md
└── README.md
```

> `sync.ps1` 会遍历 `skill/` 下的**所有子目录**（只要有 `SKILL.md`），逐个镜像到
> `~/.agents/skills/<名字>/` 和 `~/.workbuddy/skills/<名字>/`。新增技能只要建个目录放
> `SKILL.md`，再跑一次同步即可。

## 安装 / 更新

```bash
# Windows
pwsh <repo>\sync.ps1
pwsh <repo>\sync.ps1 -Project D:\proj
pwsh <repo>\sync.ps1 -SkipHooks          # 不安装/不覆盖 git core.hooksPath

# macOS / Linux
pwsh <repo>/sync.ps1
pwsh <repo>/sync.ps1 -Project ~/proj
```

改了真源就重跑一次；`sync.ps1` 是幂等的，重复执行无副作用。

> ⚠️ `sync.ps1` 自身存成 **UTF-8 with BOM**：Windows PowerShell 5.1 读无 BOM 的 UTF-8 会按 GBK
> 解析，中文字符串直接语法报错。PowerShell 7 无此限制，推荐统一用 7。

## 挂载点

| Agent | 路径 | 机制 |
|---|---|---|
| DSH / Hermes | `~/.agents/skills/<技能名>/` | 全局技能，自动发现 |
| WorkBuddy | `~/.workbuddy/skills/<技能名>/` | 全局技能，启动时扫 `SKILL.md` |
| OpenCode | `~/.config/opencode/AGENTS.md` | 标记块合并（仅在已安装时写入） |
| Cursor | `~/.cursor/rules/code-standards.mdc` | `alwaysApply: true`（仅在已安装时写入） |
| 任意项目 | `<repo>/AGENTS.md` | 项目级 stub（标记块合并） |
| 任意 git 仓库 | `core.hooksPath=<repo>/hooks` | 全局 pre-commit |

> 为什么不放 `~/AGENTS.md`：Hermes/DSH 的上下文文件是 **cwd-only、first-match-wins**，
> home 级 AGENTS.md 不会跨项目生效；跨项目规则必须走 skill。WorkBuddy 同理，只认项目根
> 的 `AGENTS.md` / `.codebuddy/CODEBUDDY.md`，所以它也走全局 skill 分发。

## 在项目里启用

```bash
# 1. 规模检查（零依赖）
pwsh <repo>/skill/code-standards/scripts/check-limits.ps1 -Path . -NoFail

# 2. 按语言挂 linter
#    TS/JS  : 复制 linters/eslint.config.mjs；TS 再合并 linters/eslint.ts.overlay.mjs
#    Java   : checkstyle -c <repo>/linters/checkstyle.xml src/
#    C/C++  : clang-tidy -p build --config-file=<repo>/linters/.clang-tidy src/*.cc
#    Python : ruff check --config <repo>/linters/ruff.toml .
```

建议在 `pre-commit` 或 CI 里跑第 1 条，否则规则会随"这次赶时间"退化。
`sync.ps1` 会把 git 全局 `core.hooksPath` 指到 `hooks/`，所以本机所有仓库默认已有这道门禁。

## 行数口径（R2 / R3）

**有效行 = 总行数 − 空行 − 纯注释行 − 仅含 `}` `)` `]` `};` 等收尾符号的行。**

- `scripts/check-limits.ps1` 是唯一仲裁；pre-commit 与 CI 都以它为准。
- eslint / checkstyle / clang-tidy 的阈值是近似护栏：Checkstyle 会把注释计入（偏严），
  ESLint 的 `skipComments` 不跳过单独 `}`。差异只在仲裁脚本不可用时参考。
- C/C++ 的预处理指令 `#include` / `#define` 算代码行，不算注释。

## 提交门禁（pre-commit）

`hooks/pre-commit.ps1` 只检查**本次提交涉及的文件**，不扫全仓，避免存量老项目直接不可提交：

| 场景 | 结果 |
|---|---|
| 新文件 > 500 行，或新文件里有 > 50 行的函数 | 拦截 |
| 存量文件本次越过 500 行 | 拦截 |
| 已超限的存量文件继续变长（R3 净增长） | 拦截 |
| 存量文件里新增一个 > 50 行的函数 | 拦截 |
| 暂存区出现疑似密钥（装了 gitleaks 时） | 拦截 |
| 存量文件缩短 / 持平，或本来就超限但没变长 | 放行 |
| 文件前 5 行写了 `standards-exempt` | 放行 |

门禁是 **fail-closed**：找不到 PowerShell 或检查脚本时拒绝提交，不再静默放行。

跳过本次检查：`git commit --no-verify`；或在没有 PowerShell 的机器上临时
`CODE_STANDARDS_ALLOW_SKIP=1 git commit ...`。
仓库若自己用 husky 等工具覆盖了 `core.hooksPath`，以该仓库配置为准，全局门禁不生效。

## 规则索引

| 编号 | 规则 | 门禁 |
|---|---|---|
| R0 | 优先级：安全/合规 > 项目 AGENTS.md > 本规范 > 技能模板 | 评审 |
| R1 | 单一职责 | 评审 |
| R2 | 函数 ≤ 50 行有效代码 | check-limits / eslint / checkstyle / clang-tidy |
| R3 | 文件 ≤ 500 行有效代码 | check-limits / eslint / checkstyle |
| R4 | 一模块一目录，单一入口，禁止跨模块深层 import | 评审 |
| R5 | 命名约定（按语言） | linter + 评审 |
| R6 | 错误处理：不吞异常、错误在边界转换 | 评审 + linter |
| R7 | 依赖方向：UI → 应用 → 领域 → 基础设施 | 评审 |
| R8 | 注释写"为什么"，公共 API 有文档注释 | 评审 |
| R9 | 提交前自检清单 | 人工 |
| R10 | 豁免 E1–E7，文件前 5 行声明 | check-limits |
| R11 | 审查节奏 L0–L3 | review-check + 台账 |
| R12 | 安全：密钥、输入校验、注入、认证授权 | gitleaks / SAST |
| R13 | 测试：改逻辑必须带测试，禁 flaky | CI |
| R14 | 依赖：lockfile、许可证、漏洞、更新 | audit / Renovate |

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

声明方式：文件**前 5 行内**写 `// standards-exempt: E1 单文件演示页`（Python 用 `#`）。
永不豁免：新生产代码套 E1、被改文件净增长、空 catch、跨模块深层 import、硬编码密钥。

## 与现有技能的关系

- `code-metrics-analysis`（Function < 50）、`static-code-analysis`（>50 行告警）与本规范**同向**，不冲突。
- 强制单文件产出的技能（`p5js`、`sketch`、`hallmark`、`architecture-diagram`、`manim-video` 等）落在 E1/E7 豁免里。
- 优先级：**安全与合规（R12）不可降级**；其后依次为项目 `AGENTS.md` > 本规范 > 技能模板。

## 审查节奏（R11）

| 层 | 触发 | 做什么 |
|---|---|---|
| L0 | 每次改完文件 | `check-limits.ps1`（pre-commit 自动跑，秒级） |
| L1 | 一个可评审单元（diff ≤ 400 行） | `review-check.ps1` + 自查清单 |
| L2 | 每模块 / 合并前 | 另起 subagent 独立评审（只给 diff + 验收标准） |
| L3 | 上线前 | 全量审计：安全、依赖、文档、性能 |

```bash
pwsh <repo>/skill/code-standards/scripts/review-check.ps1 -Path . -Ledger .review/ledger.md -Append
```

台账规则、自查清单、级别定义见 `skill/code-standards/references/review-gate.md`。

## 文档与测试

| 内容 | 位置 |
|---|---|
| 安全报告流程 | [SECURITY.md](SECURITY.md) |
| 贡献与新增规则 | [CONTRIBUTING.md](CONTRIBUTING.md) |
| 版本变更 | [CHANGELOG.md](CHANGELOG.md) |
| 许可证 | [LICENSE](LICENSE) |
| 检查器回归测试 | `pwsh ./tests/run-tests.ps1` |
| 文档一致性 | `pwsh ./tests/check-docs.ps1` |
| CI | `.github/workflows/ci.yml`（测试 + 文档 + ShellCheck + gitleaks） |

## 更新流程

1. 改 `skill/code-standards/` 下的文件
2. 跑 `pwsh ./tests/run-tests.ps1` 和 `pwsh ./tests/check-docs.ps1`
3. `git commit`（建议把这个目录纳入版本管理）
4. `pwsh sync.ps1` 分发（技能 + 全局规则 + Cursor + WorkBuddy + git 钩子）
5. 重启 agent 会话让 skill 重新加载
