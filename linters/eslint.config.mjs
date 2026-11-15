// 全局代码规范的 ESLint 规则（flat config，ESLint 9+）
// 用法：项目里 import 本文件，或把 rules 段合并进现有配置。
// 不依赖任何插件；如需 TS 类型检查再叠加 typescript-eslint。

export default [
  {
    files: ['**/*.{ts,tsx,js,jsx,mjs,cjs}'],
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
    // 声明式 UI：组件函数允许略长，但仍受 max-lines 约束；
    // 真正的拆分要求由人工评审 + R2 的“build() ≤ 50 行”把关。
    files: ['**/*.{tsx,jsx}'],
    rules: {
      'max-lines-per-function': ['off'],
    },
  },
  {
    // 测试：允许长用例
    files: ['**/*.{test,spec}.{ts,tsx,js,jsx}', '**/__tests__/**'],
    rules: {
      'max-lines-per-function': 'off',
    },
  },
];
