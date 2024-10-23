import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  plugins: [vue()],
  test: {
    globals: true,
    environment: 'jsdom',
    include: [
      'tests/unit/vue/**/*.spec.ts',
      'tests/unit/vue/**/*.spec.vue',
    ],
    exclude: [
      '**/node_modules/**',
      '**/.trunk/**',
      '**/dist/**',
      '**/.{idea,git,cache,output,temp}/**',
    ],
    setupFiles: [
      'tests/unit/vue/setup.ts',
    ],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
