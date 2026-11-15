---
name: harmony-arkui-input-focus
description: 鸿蒙 ArkUI 输入框 / 键盘 / 焦点实战经验，专治「换格时键盘退下去又弹上来」「点格子只出现编辑框但不弹键盘」「输入框浮在所有格子上面」「表尾被键盘挡住」这类表格内编辑问题。含 keepEditableState、常驻单 TextInput、onBlur 时间闸、inputFilter 白名单、自定义键盘取舍、惯性滚动解析积分等可直接照抄的代码。触发词：鸿蒙 输入框、ArkUI 键盘 收起 弹起、TextInput 焦点、单元格编辑、keepEditableState、键盘闪一下、鸿蒙 表格 输入、HarmonyOS TextInput focus。
---

# 鸿蒙 ArkUI 输入框 / 键盘 / 焦点经验

> 来源：`mixcalc-harmony`（秒算虾料 鸿蒙版）真机调试两天的成果。
> 环境：HarmonyOS SDK 6.0.1（API 21）+ 命令行 hvigor，真机 HarmonyOS 7.0。
> 场景：表格 / 多单元格录入（点一格输一格，按「下一步」跳到下一格）。

## 什么时候用这份 skill

- 要在鸿蒙里做「单元格内编辑」「表格录入」「连续输入」
- 遇到**键盘收起来再弹起来（闪一下）**
- 换格后**没拿到焦点 / 键盘不弹**
- 输入框**浮在格子上层**、拖动表格不跟手
- 系统键盘**挡住表尾/底部按钮**

## 三条铁律（90% 的问题靠这三条解决）

1. **全表只放一个 `TextInput`，放在不会被重建的位置**（最外层 `Stack`，不要放进 `ForEach`/`List`/`if` 里）。
2. **`onSubmit` 必须调 `event.keepEditableState()`**，否则按输入法的「下一步/回车」时 ArkUI 会让输入框退出编辑态 → 焦点释放 → 键盘收起 → 再抢焦点 → 又弹出 = "退下去再弹上来"。
3. **`onBlur` 里绝对不要收键盘/结束编辑**；换格瞬间旧 blur 会晚一步到达，把刚打开的新格连键盘一起关掉。

## 最小可用骨架

```ts
Stack() {                          // 最外层
  Column() { /* 表头 / 表体 / 表尾，全部自绘 Text */ }

  // 全表唯一编辑器，和表体平级：表体重排不会重建它
  if (this.editingRow >= 0 && this.editingCol >= 0) {
    TextInput({ text: this.editorText, controller: this.editorCtrl })
      .id('cellEditor')
      .type(this.editingCol === 1 ? InputType.Normal : InputType.NUMBER_DECIMAL)
      .inputFilter(this.editingCol === 1 ? '[0-9\\-到至~—、，, 号]' : '[0-9.]')
      .position({ x: this.cellLeft(this.editingCol),
                  y: HEAD_H + this.editingRow * ROW_H - this.offsetY })
      .defaultFocus(true)
      .enableKeyboardOnFocus(true)
      .enterKeyType(EnterKeyType.Next)
      .onChange((text: string) => {
        this.editingText = text;
        if (this.suppressChange) { this.suppressChange = false; return; }  // 换格塞初值时压住
        this.applyLive(text);                                              // 边输边算
      })
      .onSubmit((_k: EnterKeyType, event: SubmitEvent) => {
        event.keepEditableState();     // ★ 关键
        this.moveToNextCell();         // 只改坐标和文本，不要先关闭
      })
      .onBlur(() => {
        if (Date.now() - this.editorOpenedAt < 400) { return; }  // ★ 挡住换格瞬间的旧 blur
        this.finishEdit();
      })
  }
}
```

## 换格要点

- **不要**先 `editingRow = -1` 再设新值 —— 中间一帧输入框会被销毁，键盘必收。
- **不要**用 `ForEach` key 强制重建输入框来"刷新" —— 会闪。
- 换格后补两次焦点：`setTimeout(() => focusControl.requestFocus('cellEditor'), 60/180)`。
- 程序化改 `text` 会触发 `onChange`，用 `suppressChange` 压一次，否则会被当成用户输入提交。
- **不要用 `$$this.text` 双向绑定**（实测输入不显示/光标乱跳），用 `text + onChange` 显式同步。

## 键盘遮住底部

```ts
import { KeyboardAvoidMode } from '@kit.ArkUI';
this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);  // 默认 OFFSET 会整页上顶
```

## 输入内容限制

- `inputFilter` 是**单字符**正则白名单；设置后 `InputType` 自带过滤失效，白名单要写全。
- 任意字符：`'[\\s\\S]'`。
- 中文拼音上屏也会走这个过滤：白名单没有汉字，用户就打不进汉字。

## 自绘键盘（`customKeyboard`）该不该用

- 优点：绝对不掉键盘、键位自由（可加「下一行」「清空」「00」）。
- 缺点：平板要另做尺寸；系统输入法的联想/语音/剪贴板全没了；要字母还得再画一套。
- **结论：能用 `keepEditableState()` 就别自绘**；本项目最终回归系统输入法。

## 排查清单

1. `onFocus/onBlur` 打日志，看是否 `blur → (无 focus) → focus` 的空档。
2. `onSubmit` 里有没有 `keepEditableState()`。
3. 输入框是否被 `if`/`ForEach`/`List` 包着。
4. `onBlur` 里是否在收键盘/结束编辑。
5. 换格是否"先关再开"。
6. 格子滚出可视区后输入框是否还在（要在滚动回调里收编辑）。
7. 关键判别实验：**把 `onSubmit` 改成什么都不做**——如果键盘照样收，就是输入法动作键的默认行为，只能 `keepEditableState()`。

## 顺带记下的 ArkUI 坑

| 坑 | 解法 |
|---|---|
| `Span` 没有 `onClick`（正文内联链接） | 正文切成多个 `Text` 放 `Flex({wrap:Wrap})`，链接那段单独 `onClick` |
| 自绘表格不刷新 | `ForEach` key 带 version，但**编辑器不能在同一棵子树** |
| 惯性滚动掉帧滑不远 | 用解析积分 `Δx=(v0/k)(1-e^(-k·dt))`，别用 `v*dt` |
| 平板一半空白 | 按可用宽度断点：手机固定列宽+横滑；平板按可见列均分屏宽再贴合 |
| **隐藏列后右侧留白（像少了一列）** | 可见列总宽 < 屏宽时，按 `比例 = 屏宽 / 可见总宽` 把每个可见列放大，取整误差补给最后一列，正好铺满；详见下方「列宽铺满」 |

## 列宽铺满（隐藏列后不能留白）

表格支持"隐藏列"时，用户隐藏到只剩几列，右侧就会出现一条白边，看着像"少了一列"。规则：

```
可见总宽 = Σ(可见列宽)
若 可见总宽 < 屏宽:
    scale = 屏宽 / 可见总宽
    每列 = floor(列宽 × scale)      // 向下取整，绝不超出
    差额 = round(屏宽) − Σ(新列宽)
    差额补给最后一个可见列            // 正好铺满，不留半像素缝
否则：不动（保持横向滚动）
```

ArkTS 里落地成一个"列宽缓存"，`cw(i)` 只读缓存（否则每帧重算、且容易各算各的）：

```ts
private cachedW: number[] = [];
private cachedWidthKey: string = '';

private ensureWidths(): void {
  const key = Math.round(this.viewW) + '|' + this.vis.join(',');
  if (key === this.cachedWidthKey) return;
  this.cachedWidthKey = key;

  const out: number[] = [];
  // ① 先算基准：手机=固定列宽；平板=按可见列均分屏宽（语义 ×1.2/×0.8，夹 50–120）
  // ② 平板还要整体缩到正好等于屏宽
  // ③ 手机这边保留固定宽度，交给下一步铺满
  ...
  // 铺满（手机/平板共用）
  let sum = 0, last = -1;
  for (let i = 0; i < out.length; i++) { if (out[i] > 0) { sum += out[i]; last = i; } }
  if (sum > 0 && sum < this.viewW && last >= 0) {
    const k = this.viewW / sum;
    let newSum = 0;
    for (let i = 0; i < out.length; i++) if (out[i] > 0) { out[i] = Math.max(1, Math.floor(out[i] * k)); newSum += out[i]; }
    const diff = Math.round(this.viewW) - newSum;
    if (diff !== 0) out[last] = Math.max(1, out[last] + diff);
  }
  this.cachedW = out;
}
```

要点：
- **缓存键要包含 `viewW` 和可见性数组**，隐藏/显示列时才能重算。
- 只放大、不缩小；已超屏宽就保持滚动，别硬压（会挤掉文字）。
- 必须 floor + 补差，否则取整会让总宽差几个像素，右侧留一条细白边。
- 安卓同款：`TabletLayout.fillToWidth(widths, visible, screenWidth)`。

## 完整版文档

仓库里有一份更详细的（含原理、实测记录、代码位置索引）：

- 本地：`D:\mixcalc-harmony\docs\harmony-input-keyboard-notes.md`
- 在线：https://gitee.com/xia-guard/mixcalc-harmony/blob/main/docs/harmony-input-keyboard-notes.md
