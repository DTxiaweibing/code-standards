#!/usr/bin/env node
// standards-exempt: E1 单文件演示
function demo() {
  const a = 1;
  const b = 2;
  const c = 3;
  const d = 4;
  void [a, b, c, d];
}
demo();
