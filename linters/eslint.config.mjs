// 全局代码规范的 ESLint 规则（flat config，ESLint 9+）
// 本文件只覆盖 JS/JSX（默认 espree 解析器，零依赖）。
// TS/TSX 需要 @typescript-eslint/parser，见同目录的 eslint.ts.overlay.mjs。
//
// 用法：项目里 import 本文件，或把 rules 段合并进现有配置。
// 行数口径以 scripts/check-limits.ps1 为准；这里 skipBlankLines + skipComments 是近似。

export default [
  {
    files: ['**/*.{js,jsx,mjs,cjs}'],
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/build/**',
      '**/coverage/**',
      '**/*.gen.*',
      '**/*.d.ts',
    ],
    rules: {
      // ---- 本规范的硬规则 ----
      'max-lines': ['error', { max: 500, skipBlankLines: true, skipComments: true }],
      'max-lines-per-function': [
        'error',
        { max: 50, skipBlankLines: true, skipComments: true },
      ],

      // ---- 复杂度护栏（防止拆成 50 行但 10 层嵌套）----
      complexity: ['error', 15],
      'max-depth': ['error', 4],
      'max-params': ['error', 5],
      'max-nested-callbacks': ['error', 3],

      // ---- 可读性/正确性 ----
      eqeqeq: ['error', 'always'],
      'no-var': 'error',
      'prefer-const': 'error',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'no-empty': ['error', { allowEmptyCatch: false }],
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },
  {
    // 测试：允许长用例
    files: ['**/*.{test,spec}.{js,jsx,mjs,cjs}', '**/__tests__/**'],
    rules: {
      'max-lines-per-function': 'off',
    },
  },
];
