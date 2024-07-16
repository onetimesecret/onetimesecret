import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  root: "./src",
  plugins: [vue()],
  assetsInclude: ['**/*.woff', '**/*.woff2'], // Include font files

  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src')
    }
  },
  build: {
    outDir: '../public/web/v3/dist',
    emptyOutDir: true,
    rollupOptions: {
      output: {
        manualChunks: {
          'fonts': [
            'src/assets/fonts/zs/ZillaSlab-Regular.woff2',
            'src/assets/fonts/zs/ZillaSlab-Bold.woff2',
            'src/assets/fonts/zs/ZillaSlab-Regular.woff',
            'src/assets/fonts/zs/ZillaSlab-Bold.woff',
          ],
        },
      },
    },
  },
  base: '/v3/dist/'
})
