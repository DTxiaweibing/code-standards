# C / C++ 细则

对齐：[Google C++ Style](https://google.github.io/styleguide/cppguide.html)（含 "Functions should be short"）、[C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/)。

## 命名（Google 风格）

| 对象 | 规则 | 例 |
|---|---|---|
| 类型/类/结构体 | PascalCase | `OrderSummary` |
| 函数/方法 | PascalCase | `LoadOrder()` |
| 变量/参数 | snake_case | `order_id` |
| 成员变量 | snake_case + 下划线后缀 | `cache_` |
| 常量/枚举值 | `k` + PascalCase | `kMaxRetry` |
| 宏 | 全大写 + 项目前缀 | `MYAPP_ASSERT` |
| 文件 | snake_case | `order_service.cc` |

Google 约定：头文件 `.h`，实现 `.cc`；避免 `.cpp` 与 `.cc` 混用。

## 格式

- 2 空格缩进，行宽 80（Google）；项目统一后不要改
- 头文件自包含：先 include 自己的头，再系统头，再三方头
- 用 `#pragma once` 或 include guard，项目内统一一种

## 资源与所有权

- **禁止裸 `new` / `delete`**；用 `std::unique_ptr` / `std::shared_ptr` / 栈对象
- 所有权用类型表达：`T*` 非拥有、`T&` 非空引用、`unique_ptr<T>` 拥有
- 遵循 RAII：资源在构造函数获取、析构释放
- 禁止返回指向局部变量的指针/引用

## 函数

- 参数 ≤ 5 个，超过用 `struct` 打包
- 输入参数用 `const T&`（大对象），小对象按值
- 不修改的参数一律 `const`；成员函数能 `const` 就 `const`
- 函数 ≤ 50 行、单文件 ≤ 500 行（`linters/.clang-tidy` 强制）

## 错误处理

- 项目若禁用异常（Google 默认），用返回码 + `absl::Status` 风格；**不要**混用两种
- 禁止吞错误：每个失败分支必须处理或上抛
- 断言只用于"不可能发生"的内部不变量，不用于用户输入校验

## 未定义行为禁止项

- 未初始化变量、越界访问、悬垂引用、有符号溢出
- `reinterpret_cast` 需注释理由；`const_cast` 基本禁止
- 多线程共享数据必须用 `std::atomic` / mutex，且注释同步策略

## 与本规范的接口

- `readability-function-size.LineThreshold = 50`
- 文件 ≤ 500 行：`scripts/check-limits.ps1`
- 生成代码（protobuf `.pb.cc/.pb.h`、moc）豁免
