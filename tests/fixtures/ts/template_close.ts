// 模板字符串里出现单独的 }：不能提前把函数帧弹掉，否则函数被少算
export function wrap(json: string): string {
  const tpl = `}`;
  const a = json.trim();
  const b = a + tpl;
  return b;
}
