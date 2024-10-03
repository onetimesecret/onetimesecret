import { defineConfig, mergeConfig } from 'vite'
import baseConfig from './vite.config.ts';

export default mergeConfig(baseConfig, defineConfig({
  build: {
    rollupOptions: {
      output: {
        entryFileNames: `assets/[name].js`,
        chunkFileNames: `assets/[name].js`,
        assetFileNames: `assets/[name].[ext]`
      },
    },
  }
}));
