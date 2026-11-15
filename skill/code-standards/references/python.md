# Python 细则

对齐：[PEP 8](https://peps.python.org/pep-0008/)、[Google Python Style](https://google.github.io/styleguide/pyguide.html)、[Ruff 规则](https://docs.astral.sh/ruff/rules/)。

## 命名

| 对象 | 规则 | 例 |
|---|---|---|
| 模块/包 | snake_case | `order_service.py` |
| 函数/变量 | snake_case | `load_order` |
| 类/异常 | PascalCase | `OrderSaveError` |
| 常量 | UPPER_SNAKE | `MAX_RETRY` |
| 私有 | 单下划线前缀 | `_cache` |

- 布尔：`is_/has_/can_/should_` 前缀
- 禁止 `l`、`O`、`I` 作单字母变量（易混）

## 格式

- 4 空格缩进，行宽 100（ruff 配置）
- import 顺序：标准库 → 三方 → 本地，组内按字母
- 必须类型标注：公共函数参数与返回值（`def load(id: int) -> Order:`）
- 用 `pathlib` 而不是 `os.path`；用 f-string 而不是 `%`/`.format`

## 结构

- 包 = 目录 + `__init__.py`，`__all__` 显式导出
- 一个模块一个职责；`utils.py` 只允许放真正跨模块的纯函数，且**不得**超过 200 行
- 配置、IO、业务分离：`config.py` / `repository.py` / `service.py`
- 脚本入口用 `if __name__ == "__main__":` 并调用 `main()`

## 错误处理

```python
# 反例
try:
    save(order)
except Exception:
    pass

# 正例：只捕获能处理的，其余上抛
try:
    save(order)
except sqlite3.OperationalError as exc:
    raise OrderSaveError(order.id) from exc
```

- 禁止裸 `except:`
- `except Exception` 只允许出现在进程边界（CLI 入口、任务 worker），且必须记录
- 自定义异常继承合适基类，不要 `raise Exception(...)`

## 并发

- CPU 密集用 `ProcessPoolExecutor`，IO 密集用 `asyncio` / 线程池
- 共享可变状态必须加锁或改消息传递

## 与本规范的接口

- 文件 ≤ 500 行：`pylint --max-module-lines=500` 或 `scripts/check-limits.ps1`
- 函数 ≤ 50 行：`PLR0915`（too-many-statements，默认 50）
- 生成代码（`*_pb2.py`、`alembic/versions/`）豁免
