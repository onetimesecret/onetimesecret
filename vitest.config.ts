import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'jsdom',
    exclude: [
      '**/node_modules/**',
      '**/.trunk/**',
      '**/dist/**',
      '**/.{idea,git,cache,output,temp}/**',
    ],
    setupFiles: ['src/tests/test-setup.ts'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
