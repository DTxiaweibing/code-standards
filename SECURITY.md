# 安全策略

## 支持版本

| 版本 | 状态 |
|---|---|
| 0.2.x | 接收安全修复 |
| < 0.2 | 不再维护 |

## 报告漏洞

请**不要**通过公开 Issue 报告安全问题。使用 GitHub 的私密报告入口：

1. 打开仓库页面的 **Security** 标签
2. 选择 **Report a vulnerability**
3. 描述：影响文件、复现步骤、影响范围（是否可执行任意代码 / 读取文件 / 绕过门禁）

## 重点范围

本项目会在 `git commit` 时执行本地脚本，以下问题按高优先级处理：

- `hooks/pre-commit`、`hooks/pre-commit.ps1` 的命令注入或路径穿越
- `sync.ps1` 写入到非预期路径、覆盖用户文件
- `check-limits.ps1` / `review-check.ps1` 的拒绝服务（超大文件、异常编码导致挂起）
- 门禁被静默绕过（fail-open）且无提示

## 不在范围内

- 本机已被攻陷前提下的问题
- 需要用户主动执行 `git commit --no-verify` 才能触发的场景
- 第三方 linter（eslint / checkstyle / clang-tidy / ruff）自身的漏洞

## 处理原则

- 确认后优先修复并发布补丁版本
- 修复前不公开细节；修复后在 CHANGELOG 中致谢（如报告者同意）
