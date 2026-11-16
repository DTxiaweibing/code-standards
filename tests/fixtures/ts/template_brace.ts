// 模板字符串里出现单独的 {：不能被当成代码花括号，否则函数帧悬空、漏报
export function buildSql(where: string): string {
  const sql = `SELECT * FROM t WHERE {`;
  const a = where.trim();
  const b = a.toLowerCase();
  return sql + b;
}
