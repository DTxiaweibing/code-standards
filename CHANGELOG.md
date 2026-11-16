# 更新日志

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [0.2.1] - 2026-11-17

### Fixed

- `check-limits.ps1`：模板字符串 / C# 逐字串 / C++ 原生串 / Python 三引号里的单个花括号不再破坏函数帧匹配
  （此前 `` const tpl = `WHERE {` `` 会让整段函数漏报，`}` 则会提前截断）
- `check-limits.ps1`：`*` 不再被当作注释前缀，`*p = 1;` 这类解引用行重新计入有效行；块注释续行仍按注释处理
- `check-limits.ps1`：函数头改用「剥离字符串与注释后的行」判定，`log(") {")` 不再被误认成函数
- `pre-commit`：超限函数改按「数量」判定，只给存量超限函数加参数 / 改注解不再被误报为新增
- `pre-commit`：gitleaks ≥ 8.19 改用 `gitleaks git --staged`，旧版本仍走 `protect --staged`

### Added

- `tests/run-tests.ps1` 新增 5 个 fixture（模板串两个方向、C 解引用行、块注释续行、C++ 原生串），
  断言 36 项 → 56 项
- `check-limits.ps1` 的 JSON 输出新增 `Name` 字段，供 pre-commit 稳定识别函数

## [0.2.0] - 2026-11-16

### Added

- 新增 R12 安全、R13 测试、R14 依赖与供应链三条硬规则
- 新增 `references/security.md`、`references/testing.md`、`references/dependencies.md`
- 新增 `tests/run-tests.ps1`：check-limits 的 36 项 golden 断言（覆盖 TS/Python/Java/C++、豁免、shebang）
- 新增 `tests/check-docs.ps1`：断链、R 编号、硬编码路径、README 覆盖度检查
- 新增 GitHub Actions CI（测试 + 文档一致性 + ShellCheck + gitleaks）
- pre-commit 集成 gitleaks（已安装时对暂存区做密钥扫描）
- 新增 `LICENSE`、`SECURITY.md`、`CONTRIBUTING.md`、PR 模板
- 新增 `linters/eslint.ts.overlay.mjs`：TS 解析器与 `no-explicit-any` 规则

### Changed

- 明确 R2/R3 行数口径：有效行，`check-limits.ps1` 为唯一仲裁
- `sync.ps1` 改为跨平台：去掉 `robocopy`、`USERPROFILE` 硬依赖，支持 `-SkipHooks`
- 门禁改为 fail-closed：找不到 PowerShell / 检查脚本时拒绝提交，可用 `CODE_STANDARDS_ALLOW_SKIP=1` 临时放行
- 豁免声明从“首行”放宽到“前 5 行”，兼容 shebang / PEP 263 / `#Requires`
- C/C++ 的预处理指令 `#` 不再被误判为注释
- `sync.ps1` 只在已安装 OpenCode / Cursor 时写入对应规则文件
- README 与 SKILL 去掉硬编码的 D 盘真源路径，改用仓库相对路径或真源变量

### Fixed

- `sync.ps1 -SkipHooks` 参数未声明导致命令报错
- SKILL.md 中 review-gate 的链接少了首字母且混入 CR 字符，导致断链
- `review-check.ps1` 台账中 `\|` 转义导致列解析错位
- 技能同步计数只统计 `.agents`，导致仅安装 WorkBuddy 时误报
- Checkstyle `EmptyCatchBlock` 的 `expected|ignored` 白名单与 R6 冲突
- `review-check.ps1` 与 `review-gate.md` 的 P1/P2 分级不一致

### Removed

- `linters/eslint.config.mjs` 对 `.ts/.tsx` 的直接匹配（espree 无法解析 TS，会误报语法错误）
