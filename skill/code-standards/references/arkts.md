# ArkTS / ArkUI 细则（HarmonyOS）

对齐：[ArkTS 编程规范](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-coding-style-guide)、[ArkUI 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-development)。

## 命名

| 对象 | 规则 | 例 |
|---|---|---|
| 组件/类/接口/枚举 | PascalCase | `OrderCard` |
| 方法/变量 | camelCase | `loadOrder` |
| 常量 | UPPER_SNAKE | `MAX_RETRY` |
| 页面文件 | PascalCase 或 kebab-case（项目统一） | `OrderDetail.ets` |
| 资源 | snake_case | `order_title` |

- 禁止 `any`：ArkTS 严格模式不支持动态类型，用 `interface` / 联合类型表达
- 禁止用对象字面量伪装成类（ArkTS 要求显式类型）

## 组件结构

```ts
@Entry
@Component
struct OrderDetail {
  @State private order: Order | null = null;

  aboutToAppear(): void {
    this.order = loadOrder(this.orderId);
  }

  build() {
    Column() {
      OrderHeader({ order: this.order })
      OrderItems({ items: this.order.items })
    }
  }
}
```

- **`build()` 主体 ≤ 50 行**：超出时抽 `@Builder` 方法或独立子组件，不要堆在一个 `build()` 里
- 一个 `.ets` 文件一个 `@Component` struct 为主；页面专属的子组件可同文件，但超过 3 个就拆目录
- 状态装饰器按最小作用域选择：`@State`（组件内）→ `@Prop`（单向）→ `@Link`（双向）→ `@Provide/@Consume`（跨层）；嵌套对象变更用 `@Observed` + `@ObjectLink`
- 生命周期：`aboutToAppear` 只做初始化，网络/存储调用必须可取消或判空

## 工程结构

```
entry/src/main/ets/
├── entryability/          # UIAbility 入口
├── pages/                 # @Entry 页面
├── features/<module>/     # 业务模块（可拆 HAR）
│   ├── index.ets          # 唯一对外入口
│   ├── model/
│   ├── service/
│   └── components/
└── common/                # 跨模块工具、常量、类型
```

- 业务模块用 HAR/HSP 隔离，模块之间只通过 `index.ets` 暴露
- 禁止 `pages` 直接 import 另一个 feature 的内部文件
- 资源统一 `resources/base/{element,media,profile}`，中英文放 `resources/zh_CN`、`resources/en_US`

## 异步与线程

- 网络/文件用 `async/await` + `Promise`，不用回调嵌套
- CPU 密集（大计算、解析）放 `taskpool`，不要阻塞 UI 线程
- 页面上发起的异步任务，在 `aboutToDisappear` 里置取消标志

## 错误处理

```ts
// 反例
try { await saveOrder(order); } catch (e) { }

// 正例
try {
  await saveOrder(order);
} catch (err) {
  const e = err as BusinessError;
  hilog.error(DOMAIN, TAG, 'save failed: %{public}d %{public}s', e.code, e.message);
  promptAction.showToast({ message: $r('app.string.save_failed') });
}
```

- 禁止空 catch；`BusinessError` 必须记录 `code + message`
- 日志用 `hilog`，禁止 `console.log` 进生产包

## 与本规范的接口

- 文件 ≤ 500 行，函数 ≤ 50 行（`build()` 同样按 50 行折算）
- 生成代码（资源索引 `ResourceTable`、`BuildProfile`）豁免
- 一次性 demo（单文件 HTML）不属于 ArkTS，自然豁免 R3/R4
