# TypeScript / JavaScript 细则

对齐：[Google TypeScript Style](https://google.github.io/styleguide/tsguide.html)、[Airbnb JS Style](https://github.com/airbnb/javascript)、[ESLint 规则](https://eslint.org/docs/latest/rules/max-lines-per-function)。

## 命名

| 对象 | 规则 | 例 |
|---|---|---|
| 变量/函数 | lowerCamelCase | `loadOrder` |
| 类型/接口/组件 | PascalCase | `OrderSummary` |
| 常量（真常量） | UPPER_SNAKE | `MAX_RETRY` |
| 文件 | kebab-case | `order-service.ts` |
| 私有字段 | `#name` 或 `_name`（项目内统一一种） | `#cache` |

- 布尔：`is/has/can/should` + 形容词/过去分词：`isActive`、`hasPaid`
- 事件处理函数：`handleXxx`；传给子组件的 prop：`onXxx`
- 禁止单字母（循环 `i/j` 除外）、禁止拼音

## 格式

- 2 空格缩进，单引号，**必须分号**，尾随逗号（多行）
- 行宽 100
- import 分组并排序：node 内置 → 三方 → 本地（`@/`）；组间空一行
- 禁止用 `any`；不确定用 `unknown` + 收窄

## 结构

- 一个文件一个主要导出；同目录 `index.ts` 作为模块入口
- 组件 + 其专属 hook/类型可同目录，但**不要**把 5 个业务模块塞进 `components/`
- 副作用（网络、存储、时间、随机）只出现在适配层，方便测试

## 错误处理

```ts
// 反例：吞掉
try { await save(); } catch (e) {}

// 正例：边界转换 + 单次日志
try {
  await save(order);
} catch (cause) {
  throw new OrderSaveError(order.id, { cause });
}
```

- 禁止 `catch (e: any)` 后 `any` 透传
- Promise 不允许悬空：`void promise` 要显式注释理由

## 异步

- 优先 `async/await`，避免 `.then` 链
- 并行用 `Promise.all`，不要串行 `await`
- 取消用 `AbortController`，不要靠标志位轮询

## 测试

- 文件 `*.test.ts` 与源码同目录
- 测试函数不受 50 行限制，但一个 `it` 只断言一个行为

## 与本规范的接口

- `max-lines` = 500、`max-lines-per-function` = 50（见 `linters/eslint.config.mjs`）
- 生成代码（`*.gen.ts`、`*.d.ts`）豁免 R2/R3
- 一次性 HTML demo 豁免 R3/R4（见 `exceptions.md`）
