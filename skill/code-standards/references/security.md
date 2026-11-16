# 安全细则（R12）

安全条款**不可被项目约定降级**。这里的每一条都是"违反即 P0/P1"，不是建议。

## 硬性要求

| # | 要求 | 反例 |
|---|---|---|
| S1 | 密钥、token、私钥、连接串**不得出现在代码/配置/测试/注释里** | `const API_KEY = 'sk-...'`、`.env` 提交 |
| S2 | 密钥从环境变量或密钥管理服务读取，缺失时**启动失败**而不是用默认值 | `process.env.KEY \|\| 'dev-key'` |
| S3 | 所有外部输入在**边界**校验：类型、长度、范围、枚举白名单 | 直接 `exec(req.query.cmd)` |
| S4 | SQL 一律参数化；禁止字符串拼接查询 | `"SELECT * FROM t WHERE id=" + id` |
| S5 | 输出到 HTML/SQL/Shell/日志前必须转义或编码 | `innerHTML = userInput` |
| S6 | 文件路径必须规范化并限制在允许目录内（防穿越） | `open(base + userPath)` |
| S7 | 出站请求用白名单/固定 host（防 SSRF）；禁止请求内网元数据地址 | 用户可传任意 URL 给后端 fetch |
| S8 | 认证/授权在服务端校验；前端隐藏按钮不算权限控制 | 只在前端判断 `isAdmin` |
| S9 | 日志与错误响应不得包含密钥、token、PII、完整堆栈 | `res.send(err.stack)` |
| S10 | 反序列化只接受已知类型；禁止对不可信数据用原生反序列化 | Java 原生 `ObjectInputStream` |
| S11 | 新增依赖必须通过漏洞与许可证检查（见 R14） | 引入有已知 CVE 的包 |
| S12 | 文件权限最小化；临时文件用完即删；不把凭据写入缓存 | 世界可读的私钥文件 |

## 工具（有则必挂，无则说明）

| 语言 | 密钥扫描 | 依赖漏洞 | 静态分析 |
|---|---|---|---|
| 通用 | `gitleaks protect --staged` | — | Semgrep / CodeQL |
| TS/JS | gitleaks | `npm audit --audit-level=high` / `pnpm audit` | `eslint-plugin-security` |
| Python | gitleaks | `pip-audit` / `uv pip audit` | `bandit` |
| Java | gitleaks | OWASP Dependency-Check | SpotBugs + FindSecBugs |
| Go | gitleaks | `govulncheck ./...` | `gosec` |
| Rust | gitleaks | `cargo audit` | `cargo clippy`（含安全 lint） |
| C/C++ | gitleaks | — | clang-tidy `bugprone-*` + ASan/UBSan |

## 分级

| 级别 | 例子 | 处理 |
|---|---|---|
| P0 | 密钥泄漏、SQL 注入、认证绕过、命令注入、SSRF 打到内网 | 停手修，必要时轮换凭据 |
| P1 | 依赖存在高危 CVE、缺少输入校验、错误响应泄露堆栈 | 本任务内修 |
| P2 | 安全相关告警未处理、缺少速率限制 | 记台账，排期 |

## 评审时只问三句

1. 这个输入从哪来，谁校验？
2. 这段输出去了哪，转义了吗？
3. 这个失败会不会 fail-open（出错后放行）？
