---
name: android-custom-table
description: 安卓大表格（几百个格子、30+ 行）的实现铁律：必须自绘（一个自定义 View + Canvas），不能用原生 TableLayout/RecyclerView 每格一个控件；配合「全表共用一个 EditText 编辑框」做单元格录入；再用「初速度+目标距离反解衰减系数 + 解析积分」做惯性滑动。含猛甩丢惯性、滑不到底、快速滑动反而更短、InputFilter 白名单、表尾配色等实战结论。触发词：安卓 表格 卡顿、自绘表格、Canvas 画表格、EditText 太多、单元格编辑、惯性 滑动 fling、滑不到底、OverScroller、VelocityTracker。
---

# 安卓大表格：自绘 + 共用编辑框 + 惯性

> 来源：`mixcalc-lab`（秒算虾料 安卓版）11 列 × 30 行 = 330 格的真实实现。
> 同一套结论在鸿蒙版也验证过（见 `harmony-arkui-input-focus`）。

## 0. 三条铁律

1. **格子多了必须自绘**：一个自定义 `View`（或 `ViewGroup`）用 `Canvas` 画一切，**不要** `TableLayout` / `RecyclerView` / `GridView` 每个格子放一个 `TextView`。
2. **全表只放一个 `EditText`**，哪个格要编辑就 `layout()` 到它上面——绝不给每个格子配一个 `EditText`。
3. **惯性别用 `OverScroller` 的封顶逻辑**，自己按「初速度 + 目标距离 → 反解衰减系数 → 解析积分」推进。

## 1. 为什么大表格不能用原生控件

| 方案 | 330 格的后果 |
|---|---|
| `TableLayout` + 每格 `TextView` | 330 个 View，测量/布局/绘制全走一遍，滚动必卡；`LinearLayout` 嵌套还会触发多次 measure |
| `RecyclerView` + 每格一个 item | 复用能撑住，但**冻结列、表头吸顶、表尾吸底、跨行列对齐**都要自己再写一遍，等于绕回自绘 |
| 每格一个 `EditText`（想直接编辑） | 最致命：每个 `EditText` 自带输入连接、焦点管理、`TextWatcher`；330 个直接把内存和绘制拖垮，安卓上这就是"爆"的主因 |
| **自绘 `Canvas` + 一个共用 `EditText`** | 一个 View 画 330 格：`onDraw` 里 `drawRect`/`drawText`；编辑时只移动那一个 `EditText` |

自绘还要一起解决（这些原生控件本来会帮你做）：

- 横滚/纵滚两个偏移量（`offsetX/offsetY`），表头钉在 y=0、表尾钉在底部
- 冻结列：绘制固定列时不加 `offsetX`
- 命中测试：`onTouchEvent` 里把坐标换算成（行、列）
- 边界 clamp、惯性、长按
- 编辑器跟随滚动（`onScrolled` 里重新 `layout`），滚出可视区就收起

## 2. 共用编辑器（单元格录入的关键）

```java
// 整个表一个 EditText，默认 GONE
editText = new EditText(context);
editText.setVisibility(View.GONE);
editText.setBackgroundResource(R.drawable.cell_border); // 绿框
editText.setGravity(Gravity.CENTER);
editText.setSingleLine(true);
editText.setImeOptions(EditorInfo.IME_ACTION_NEXT);

// 点哪格就贴到哪格
void begin(int row, TableColumn column) {
    ...
    editText.setInputType(column.inputType);
    if ("shed_number".equals(column.id)) {
        editText.setFilters(new InputFilter[]{SHED_NUMBER_FILTER});  // 按列切过滤器
    } else {
        editText.setFilters(new InputFilter[0]);                     // 换格要重置！
    }
    editText.setText(原值);
    editText.setSelection(editText.getText().length());               // 光标放末尾
    editText.setVisibility(View.VISIBLE);
    layoutChild();                                                    // 按 cellRect 布局
    editText.requestFocus();
    imm.showSoftInput(editText, 0);
}

void layoutChild() {
    Rect r = table.getCellRect(row, column.id);
    editText.measure(EXACTLY(r.width()), EXACTLY(r.height()));  // 先 measure
    editText.layout(r.left, r.top, r.right, r.bottom);          // 再 layout
}
```

要点：

- **先 `measure` 再 `layout`**，否则内部文本布局是 0×0，`Gravity.CENTER` 不居中（这个坑在自绘按钮上也踩过，见第 5 节）。
- 文本一变就回调宿主重算（"边输边算"），但 `setText` 时要用 `suppress` 标志压住回调，否则一打开就当提交。
- `dirty` 标记：只点一下没输入就不提交。
- 换格时**先提交上一格**再打开新格，键盘不闪。
- 滚动时重算矩形；格子滚出可视区就 `end()` 收起。

## 3. 惯性滑动：从「猛甩丢惯性」到解析积分

### 症状

| 症状 | 根因 |
|---|---|
| 慢慢滑有惯性，**手速一快就没惯性** | 测速被 `maxUnits` 截断，或跑道封顶把速度砍成 0 |
| 滑得再快也**到不了底** | `D = v0/k` 的物理上限不够（v0 被截断 / k 太大） |

**判别**：v0 越大滑得越远吗？"越大反而越短" 一定是速度被截断。

### 错误做法

```java
int flingX = capFlingVelocity(vx, runwayX);      // 按剩余距离砍速度：边界情况会算出 0/NaN
scroller.fling(offsetX, offsetY, -flingX, ...);  // OverScroller 内部还有一次速度上限
```

```java
offset -= v * dt;   // dt 被 clamp 后，掉帧就少走距离
v *= exp(-k * dt);
```

### 正确做法：k = v0 / D + 解析积分

```
v(t) = v0·e^(-k·t)      位移 D = v0/k      →  k = v0 / D
每帧：Δx = (v0/k)·(1 − e^(−k·dt))      （解析积分，掉帧也精确）
```

```java
private static final float FLING_NATURAL_K = 4.0f;      // 总距离 = v0/K；4.5 更黏，3.5 更滑
private static final float FLING_MAX_VELOCITY = 25000f; // 别用系统 8000，猛甩会被截

private boolean flinging;
private float flingVx, flingVy, flingKx, flingKy, flingAccX, flingAccY;
private long flingLastTime;

private final Runnable flingRunnable = new Runnable() {
    @Override public void run() {
        if (!flinging) return;
        long now = SystemClock.uptimeMillis();
        float dt = (now - flingLastTime) / 1000f;
        flingLastTime = now;
        if (dt <= 0f) { postOnAnimation(this); return; }
        if (dt > 0.25f) dt = 0.25f;

        float ex = (float) Math.exp(-flingKx * dt);
        float ey = (float) Math.exp(-flingKy * dt);
        float moveX = flingKx > 0f ? (flingVx / flingKx) * (1f - ex) : 0f;
        float moveY = flingKy > 0f ? (flingVy / flingKy) * (1f - ey) : 0f;
        flingVx *= ex;  flingVy *= ey;

        flingAccX -= moveX;  flingAccY -= moveY;
        int stepX = (int) flingAccX, stepY = (int) flingAccY;
        flingAccX -= stepX;  flingAccY -= stepY;

        boolean moved = scrollByTable(stepX, stepY);       // 内部 clamp 边界
        if (offsetX <= 0 || offsetX >= maxScrollX) { flingVx = 0; flingAccX = 0; }
        if (offsetY <= 0 || offsetY >= maxScrollY) { flingVy = 0; flingAccY = 0; }

        int stop = dp(15);
        if (!moved || (Math.abs(flingVx) < stop && Math.abs(flingVy) < stop)) { stopFling(); return; }
        postOnAnimation(this);
    }
};

private void startFling(float vx, float vy) {
    stopFling();
    if (Math.abs(vx) < dp(60) && Math.abs(vy) < dp(60)) return;
    int runwayX = vx > 0 ? offsetX : (maxScrollX - offsetX);
    int runwayY = vy > 0 ? offsetY : (maxScrollY - offsetY);
    flingVx = vx;  flingVy = vy;
    flingKx = computeK(vx, runwayX);
    flingKy = computeK(vy, runwayY);
    if (flingVx != 0 && flingKx <= 0) flingVx = 0;
    if (flingVy != 0 && flingKy <= 0) flingVy = 0;
    if (flingVx == 0 && flingVy == 0) return;
    flinging = true;  flingAccX = 0;  flingAccY = 0;
    flingLastTime = SystemClock.uptimeMillis();
    postOnAnimation(flingRunnable);
}

private float computeK(float v, int runway) {
    float absV = Math.abs(v);
    if (absV <= 0 || runway <= 0) return 0f;
    float natural = absV / FLING_NATURAL_K;      // 自然该滑多远
    float distance = Math.min(natural, runway);  // 但不越过边界 → 到边界速度正好为 0
    return distance < 1f ? 0f : absV / distance;
}

private void stopFling() {
    flinging = false;
    flingVx = flingVy = flingKx = flingKy = flingAccX = flingAccY = 0;
    removeCallbacks(flingRunnable);
}
```

测速：

```java
velocityTracker.computeCurrentVelocity(1000, FLING_MAX_VELOCITY);
startFling(velocityTracker.getXVelocity(), velocityTracker.getYVelocity());
```

生命周期：`ACTION_DOWN` / `ACTION_CANCEL` / `onDetachedFromWindow` 都要 `stopFling()`。

### 参数

| 参数 | 作用 | 值 |
|---|---|---|
| `FLING_NATURAL_K` | 总距离 = v0/K，越小越滑 | 4.0（对齐鸿蒙），黏一点 4.5，滑一点 3.5 |
| `FLING_MAX_VELOCITY` | 测速上限 | 25000 |
| 起始 / 停止阈值 | | 60 dp/s / 15 dp/s |
| `dt` 上限 | 防切后台回来大跳 | 0.25s |

### 排障备忘

- **别轻信"某个旧版本手感更好"**：本项目查过 `git diff --stat v0.3.3 <0.3.2 提交> -- .../table` **完全无差异**（0.3.3 只改了版本号和菜单）；真差别是"数据变多 → `maxScrollY` 变大，旧封顶速度滑不到了"。
- log 打 `v0/k/剩余距离`，一眼看出是"速度被截断"还是"衰减太快"。
- 别在自绘 fling 上再套 `ValueAnimator`/`Scroller`，会出现二次削峰。

## 4. 输入限制：`InputFilter` 白名单

```java
private static final String SHED_ALLOWED = " -到至~—、，,号";
private static final InputFilter SHED_NUMBER_FILTER =
    (src, start, end, dest, dstart, dend) -> {
        StringBuilder sb = new StringBuilder();
        for (int i = start; i < end; i++) {
            char c = src.charAt(i);
            if ((c >= '0' && c <= '9') || SHED_ALLOWED.indexOf(c) >= 0) sb.append(c);
        }
        return sb.length() == end - start ? null : sb.toString();
    };
```

- 按列设置：棚号挂白名单，其它列 `setFilters(new InputFilter[0])`（换格必须重置，否则过滤器串列）。
- 数字列用 `InputType.TYPE_CLASS_NUMBER | TYPE_NUMBER_FLAG_DECIMAL` 即可，不需要自定义过滤器。
- 中文拼音上屏也走过滤器：白名单没汉字，用户就打不进汉字。

## 5. 其他踩过的小坑

| 坑 | 现象 | 解法 |
|---|---|---|
| 手动 `layout()` 的 `TextView` | 文字永远不垂直居中 | 先 `measure()` 再 `layout()`；或干脆自绘，用 `fontMetrics` 算基线：`baseline = h/2 - (fm.ascent + fm.descent)/2` |
| 表尾整行配色 | 和鸿蒙版不一致 | `CellStyle.footerFill()` 返回浅绿 `0xFFEAF3EC`，文字 `0xFF1F6B30` |
| 顺序录入限制 | 跳行录入 | `isCellEditable()` 里加"前面有空行且本行空 → 拦截"；点击 / 键盘「下一步」跨行 / 「下一行」按钮三处都要拦，只拦空行（有数据的行永远放行） |

## 相关代码（mixcalc-lab）

- `app/src/main/java/com/shrimpfarm/app/mixcalc/table/MixCalcTableView.java` — 自绘表格、滚动、惯性、命中测试
- `.../table/CellEditorOverlay.java` — 共用 `EditText`、白名单、提交
- `.../table/CellStyle.java` — 画笔与配色（表尾浅绿）
- `.../table/PillButtonView.java` — 自绘胶囊按钮（`fontMetrics` 精确居中）
- `.../Misc/TableMetrics.java`（`TableMetrics.java`）— 列宽/行高/滚动上限
