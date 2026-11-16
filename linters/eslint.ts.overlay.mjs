// TS/TSX 追加配置（可选）：需要先安装
//   npm i -D eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin
//
// 用法（项目 eslint.config.mjs）：
//   import base from 'standards/linters/eslint.config.mjs';
//   import ts from 'standards/linters/eslint.ts.overlay.mjs';
//   export default [...base, ...ts];
//
// 行数口径以 scripts/check-limits.ps1 为准；这里 skipBlankLines + skipComments 是近似。

import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';

export default [
  {
    files: ['**/*.{ts,tsx,mts,cts}'],
    ignores: ['**/node_modules/**', '**/dist/**', '**/build/**', '**/coverage/**', '**/*.gen.*', '**/*.d.ts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: { ecmaVersion: 'latest', sourceType: 'module' },
    },
    plugins: { '@typescript-eslint': tsPlugin },
    rules: {
      'max-lines': ['error', { max: 500, skipBlankLines: true, skipComments: true }],
      'max-lines-per-function': [
        'error',
        { max: 50, skipBlankLines: true, skipComments: true },
      ],
      complexity: ['error', 15],
      'max-depth': ['error', 4],
      'max-params': ['error', 5],
      'max-nested-callbacks': ['error', 3],

      eqeqeq: ['error', 'always'],
      'prefer-const': 'error',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'no-empty': ['error', { allowEmptyCatch: false }],
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },
  {
    // 声明式 UI：组件树本身就长，给一个兜底阈值，而不是完全关闭
    files: ['**/*.tsx'],
    rules: {
      'max-lines-per-function': [
        'error',
        { max: 150, skipBlankLines: true, skipComments: true },
      ],
    },
  },
  {
    files: ['**/*.{test,spec}.{ts,tsx}', '**/__tests__/**'],
    rules: {
      'max-lines-per-function': 'off',
    },
  },
];
