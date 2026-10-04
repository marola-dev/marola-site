import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import tseslint from 'typescript-eslint';

export default defineConfig(
  { ignores: ['site/static/**', 'site/dist/**', 'site/src/catalog.ts', '.claude/**', 'node_modules/**'] },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: { parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname } },
    rules: {
      '@typescript-eslint/restrict-template-expressions': ['error', { allowNumber: true }],
      // `config.style || DEFAULT`: an empty string means unset here
      '@typescript-eslint/prefer-nullish-coalescing': ['error', { ignorePrimitives: { string: true } }],
    },
  },
  {
    files: ['tests/**'],
    rules: {
      // node:test's test() returns a promise the runner already awaits
      '@typescript-eslint/no-floating-promises': 'off',
      // stubs of DOM and Mapbox methods do nothing on purpose
      '@typescript-eslint/no-empty-function': 'off',
      // stub types are looser or tighter than the bundle's runtime values
      '@typescript-eslint/no-unnecessary-condition': 'off',
      '@typescript-eslint/no-unnecessary-type-parameters': 'off',
      '@typescript-eslint/no-confusing-void-expression': 'off',
    },
  },
);
