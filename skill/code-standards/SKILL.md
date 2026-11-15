---
name: code-standards
description: Enforce code size, structure, and naming rules.
version: 0.1.0
author: DTxiaweibing, DeepSeek Harness
license: MIT
platforms: [windows, linux, macos]
metadata:
  hermes:
    tags: [code-standards, structure, limits, review, lint]
    related_skills: [code-review-analysis, static-code-analysis, refactor-legacy-code]
---

# Code Standards（个人工程规范）

任何写**生产代码**的任务都适用。目标不是"好看"，是**可读、可拆分、可被下一个人接手**。

## 何时使用

- 新建项目、新增模块、修改函数体
- 代码评审、重构、给 agent 补功能
- 拿不准"这段该不该拆"的时候

**不适用于**：一次性交付物（HTML demo、图表、原型、单文件渲染脚本）——见 `references/exceptions.md`。

## 优先级（R0）

1. 项目根 `AGENTS.md` 里的显式约定
2. 本规范
3. 技能自带的模板/示例代码

冲突时上层覆盖下层，并在回答里一句话说明依据。任何人不得用"技能让我这么写"来抵消本规范。

## 硬规则

### R1 单一职责
一个函数只做一件事，一个文件只承担一个角色（模型 / 服务 / 适配 / 视图）。判断标准：能否用一句话命名，且不含"并且"。

### R2 函数长度（≤ 50 行）
单个函数/方法 **≤ 50 行有效代码**。有效 = 剔除空行、纯注释行、单独成行的 `}` `)` `};`。

超限时按顺序尝试：
1. 提取私有方法（按"一段可命名的步骤"切）
2. 抽参数对象（参数 > 5 个时）
3. 抽策略/状态机

**禁止**用压缩空行、塞进一行、内联匿名函数来规避计数。

### R3 文件长度（≤ 500 行）
单文件 **≤ 500 行**。存量文件不强制重写，但**改动时不得净增长**；新增功能必须落到新文件。

### R4 模块边界（一模块一目录）
一个模块 = 一个目录，目录内只有一个对外入口（`index.ts` / `__init__.py` / `mod.rs` / 包内唯一 public 类）。

```
feature/order/
├── index.ts       # 唯一对外入口
├── model.ts       # 领域模型（不依赖框架）
├── service.ts     # 用例编排
├── repository.ts  # 基础设施适配（DB/HTTP）
└── ui/            # 视图层，只 import index.ts
```

**禁止跨模块深层导入**：只能 import 对方入口，不能 import `other-module/internal/*`。

### R5 命名
用完整单词，禁止拼音缩写（领域术语除外，如 `gonghao` 不行、`shedNumber` 可以）。布尔值用 `is/has/can/should` 前缀。命名细则按语言见 `references/`。

### R6 错误处理
不允许空 `catch`、不允许吞异常、不允许 `catch (Exception e) {}` 后继续跑。错误在边界处转换（HTTP/DB → 领域错误），内部只抛领域错误。日志只在边界打一次，不逐层重复。

### R7 依赖方向
UI → 应用/用例 → 领域 → 基础设施（依赖倒置）。领域层不得反向依赖 UI、框架、数据库驱动。

### R8 注释
注释解释 **why**（约束、坑、外部协议原因），不复述代码。公共 API 必须有用途/参数/返回说明。`TODO` 必须带负责人或 issue 号，否则不写。

### R9 提交前自检
改完代码必须跑 `scripts/check-limits.ps1`（或项目里的 linter），把超限项处理掉或明确豁免。结果写进提交说明或回复。

### R10 豁免
文件顶部一条：`// standards-exempt: <具体理由>`（Python 用 `#`）。**一个文件只允许一条**，理由必须具体（"这是生成的 protobuf 代码"可以，"临时方便"不行）。评审有权拒绝。

### R11 审查节奏
不等到项目结束才审，也不逐行审。按“可评审单元”分四层：

| 层 | 触发 | 范围 | 做法 | 成本 |
|---|---|---|---|---|
| L0 门禁 | 每次改完文件 | linter / 类型 / check-limits | 脚本自动跑 | 秒级 |
| L1 任务自查 | 一个可评审单元完成（diff ≤ 400 行） | 本次 diff + 测试 + 规范红线 | 跑 `scripts/review-check.ps1` + 对照 `references/review-gate.md` 清单 | 2–5 分钟 |
| L2 独立评审 | 每个模块 / 每 3–5 个任务 / 合并前 | 跨文件、架构边界、错误处理 | 另起 subagent，只给 diff + 验收标准，不给会话历史 | 10–20 分钟 |
| L3 发布审计 | 里程碑 / 上线前 | 安全、依赖、文档、性能 | 全量审计，不逐行 | 半天 |

- 可评审单元的判据：能用一个 commit 描述、能独立回滚、diff ≤ 400 行
- 完成 = L1 清单全过 + 脚本无新增 P0/P1；过不了不许声称完成
- 每次审查必须更新台账 `.review/ledger.md`，否则视为未完成
- 只改文案/注释/格式且 L0 无变化时，可跳过 L1

## 提交前清单

- [ ] 没有函数 > 50 行
- [ ] 没有新增文件 > 500 行
- [ ] 新模块独立目录 + 单一入口
- [ ] 没有跨模块深层 import
- [ ] 没有空 catch / 吞异常
- [ ] 公共 API 有注释，TODO 有归属
- [ ] `check-limits.ps1` 通过（或已按 R10 豁免）

## 语言细则

| 语言 | 文件 |
|---|---|
| TypeScript / JavaScript | `references/typescript.md` |
| Python | `references/python.md` |
| Java | `references/java.md` |
| C / C++ | `references/cpp.md` |
| ArkTS / ArkUI | `references/arkts.md` |
| 豁免与例外 | `references/exceptions.md` |
| 审查门禁与台账 | eferences/review-gate.md |

## 反模式（见到就改）

| 反模式 | 为什么错 |
|---|---|
| 800 行的 `util.ts` | 职责不清，谁都不敢改 |
| 一个函数里 6 层嵌套 `if` | 控制流不可读，测试写不出来 |
| `catch (e) { }` | 错误被静默吞掉，线上无法排查 |
| `import { x } from '../other/internal/x'` | 模块边界被击穿 |
| 500 行里 300 行是注释掉的旧代码 | 有 git，不需要留尸 |
| 为了过 linter 把两行合成一行 | 规避规则比违反规则更糟 |
