# 依赖与供应链细则（R14）

新增一个依赖 = 引入一份长期维护责任 + 一份许可证义务 + 一份攻击面。

## 硬性要求

| # | 要求 |
|---|---|
| D1 | lockfile 必须提交：`package-lock.json` / `pnpm-lock.yaml` / `poetry.lock` / `uv.lock` / `go.sum` / `Cargo.lock` |
| D2 | 禁止裸 `npm install -g`、`pip install` 后不写进依赖清单 |
| D3 | 新增依赖必须在 PR 里说明：为什么需要、为什么不能用现有依赖、许可证是什么 |
| D4 | 许可证白名单：MIT / Apache-2.0 / BSD-2/3 / ISC / MPL-2.0；GPL/AGPL/SSPL 及"自定义商用限制"需人工批准 |
| D5 | 新增依赖前查已知漏洞（见工具表）；有高危 CVE 的直接拒绝 |
| D6 | 禁止依赖未发布到官方 registry 的包、可疑拼写包（typosquatting）、个人 fork 的 git 分支 |
| D7 | 大版本升级单独 PR，不与功能改动混在一起 |
| D8 | 安全更新（patch/minor 内）按月批量跟进，不积压 |
| D9 | 发布物需要 SBOM 时，用 CycloneDX/SPDX 生成并随版本归档 |

## 新增依赖评审清单

- [ ] 真的需要吗？标准库/现有依赖能否覆盖
- [ ] 维护是否活跃（近 12 个月有提交/发版）
- [ ] 传递依赖有多少、是否引入已知高危
- [ ] 许可证在白名单内
- [ ] 包体积/运行时代价可接受
- [ ] 有 lockfile 且版本可复现

## 工具

| 语言 | 漏洞扫描 | 许可证 | 更新 |
|---|---|---|---|
| TS/JS | `npm audit --audit-level=high` | `license-checker` | Renovate / Dependabot |
| Python | `pip-audit` | `pip-licenses` | Renovate / Dependabot |
| Java | OWASP Dependency-Check | `license-maven-plugin` | Renovate / Dependabot |
| Go | `govulncheck ./...` | `go-licenses report` | Renovate / Dependabot |
| Rust | `cargo audit` | `cargo deny check licenses` | Renovate / Dependabot |
| C/C++ | `osv-scanner`（扫描 lockfile/SBOM） | — | Renovate / Dependabot |

## 供应链底线

- 构建与发布使用固定版本的工具链（`.nvmrc` / `rust-toolchain.toml` / `go.mod` / `gradle wrapper`）
- CI 使用官方 Action 并固定到 commit SHA 的场景下，优先用版本 tag + 最小权限 `permissions`
- 不在 CI 日志里打印 token；fork PR 不给 secrets
- 高危漏洞修复优先于新功能（P0/P1）
