// ESLint (flat config): JavaScript recommended rules plus the React hooks rules.
import js from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import globals from 'globals';

export default [
  { ignores: ['dist/**', 'node_modules/**', 'coverage/**'] },
  {
    files: ['**/*.{js,jsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.browser },
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    plugins: { 'react-hooks': reactHooks, 'react-refresh': reactRefresh },
    rules: {
      ...js.configs.recommended.rules,
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      // JSX elements count as uses of the imported components.
      'no-unused-vars': ['error', { varsIgnorePattern: '^[A-Z_]', argsIgnorePattern: '^(_|[A-Z])', ignoreRestSiblings: true }],
    },
  },
  {
    files: ['*.config.js', 'vite.config.js', 'tailwind.config.js', 'postcss.config.js'],
    languageOptions: { globals: { ...globals.node } },
  },
  {
    files: ['src/**/*.test.{js,jsx}', 'src/test/**'],
    languageOptions: { globals: { ...globals.node } },
  },
];
