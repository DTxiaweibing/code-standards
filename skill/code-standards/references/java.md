# Java 细则

对齐：[阿里巴巴 Java 开发手册](https://developer.aliyun.com/ask/318300)（强制项）、[Google Java Style](https://google.github.io/styleguide/javaguide.html)。

## 命名

| 对象 | 规则 | 例 |
|---|---|---|
| 类 | UpperCamelCase | `OrderService` |
| 方法/变量 | lowerCamelCase | `loadOrder` |
| 常量 | UPPER_SNAKE | `MAX_RETRY` |
| 包 | 全小写，单数 | `com.example.order` |
| 抽象类 | `Abstract` / `Base` 前缀 | `AbstractHandler` |
| 异常 | `Exception` 后缀 | `OrderNotFoundException` |
| 测试 | `Test` 后缀，被测算类名 + Test | `OrderServiceTest` |

- 布尔字段**不要**加 `is` 前缀（POJO 序列化会出坑），getter 用 `isXxx()`
- 禁止拼音与无意义缩写；`tmp`、`a1`、`data1` 不允许

## 格式

- 缩进 4 空格（Google 用 2，按项目统一，**不要混**）
- 行宽 120（Checkstyle 配置）
- 一个文件一个顶层 public 类
- import 不用 `*`；删除未使用 import

## 结构

- `controller` / `service` / `repository` / `domain` 分层，domain 不依赖 Spring
- DTO 与实体分离；禁止把 `Entity` 直接返回给前端
- 构造器注入优于字段注入（`@Autowired` 字段注入不允许）

## 错误处理

```java
// 反例
try { save(o); } catch (Exception e) { /* ignore */ }

// 正例
try {
    repository.save(order);
} catch (DataAccessException e) {
    throw new OrderSaveException(order.getId(), e);
}
```

- 禁止 `catch (Exception e) {}`；`e.printStackTrace()` 不允许进生产
- 自定义异常带错误码与上下文，不打日志（由边界统一打）
- 资源用 try-with-resources

## 集合与并发

- 初始化集合指定容量（已知大小时）
- `HashMap` 遍历用 `entrySet()`；不要在 for 里 `map.get(key)`
- 并发场景用 `ConcurrentHashMap` / `AtomicXxx`，不要用 `synchronized` 包住整个方法

## 与本规范的接口

- 方法 ≤ 50 行（比阿里的 80 更严，本规范优先）
- 文件 ≤ 500 行：`checkstyle.xml` 的 `FileLength`
- Lombok 生成的代码不计入行数
