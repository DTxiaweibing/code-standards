# 参与贡献

## 本地验证

改完任何文件，至少跑：

```bash
pwsh ./tests/run-tests.ps1     # check-limits 的 golden 测试
pwsh ./tests/check-docs.ps1    # 断链 / R 编号 / 硬编码路径 / README 覆盖
```

Windows PowerShell 5.1 也可运行；PowerShell 7 更快。若你改的是 `hooks/pre-commit`，再跑：

```bash
shellcheck hooks/pre-commit
```

## 提交信息

采用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)：

```
feat(checker): 支持 shebang 后第 2 行豁免
fix(sync): 补上 -SkipHooks 参数
docs(skill): 新增 R12 安全条款
test(checker): 增加 C++ 预处理指令用例
```

类型：`feat` / `fix` / `docs` / `test` / `refactor` / `chore` / `perf`。

## 新增一条规则

1. 在 `skill/code-standards/SKILL.md` 增加 `### Rnn 名称`，只写原则 + 反例 + 指向细则
2. 细则放 `skill/code-standards/references/<主题>.md`
3. 能自动化的，在 `linters/` 或 `scripts/` 落地，并说明仲裁工具
4. 在 `tests/` 加用例（能自动化的规则必须有测试）
5. 更新 `README.md` 的规则索引和 `CHANGELOG.md`
6. 跑 `pwsh ./sync.ps1` 分发（本机需要时）

`tests/fixtures/` 下的文件是**故意不合规**的测试输入，不要"修好"它们。

## 评审

- 先看 `skill/code-standards/references/review-gate.md` 的级别定义
- P0/P1 必须修；P2 记台账；P3 可延期但要有触发条件
- 不同意某条规则：先改规范和测试，再改实现，禁止只改实现
