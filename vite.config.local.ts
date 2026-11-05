// vite.config.local.ts

import { defineConfig, mergeConfig } from 'vite';
import baseConfig from './vite.config';

/**
 * Local Vite Configuration
 *
 * Builds the same chunks as `vite.config.ts`, but with predictable file
 * names instead of content hashes (e.g. `assets/main.js`). Everything else,
 * including minification, code splitting and the manifest the backend reads
 * (apps/web/core/views/helpers/vite_manifest.rb), comes from the base config,
 * so the backend serves either build without changes.
 *
 * Differences from the base config:
 * - File names without content hashes
 * - `__BUILD_TIME__` defined as the ISO timestamp of the build
 *
 * Usage:
 * Run `pnpm run build:local`. The output is written to `public/web/dist`,
 * which is gitignored, so it is not committed.
 *
 * Note: the base config is a callback (`defineConfig(env => ...)`), and
 * Vite's `mergeConfig` refuses callbacks, so this config is a callback too
 * and resolves the base with the same env before merging.
 *
 */
export default defineConfig(async (env) =>
  mergeConfig(
    typeof baseConfig === 'function' ? await baseConfig(env) : baseConfig,
    defineConfig({
      build: {
        // Generate sourcemaps for easier debugging
        sourcemap: true,
        rolldownOptions: {
          output: {
            // Generate predictable filenames without hashes
            entryFileNames: `assets/[name].js`,
            chunkFileNames: `assets/[name].js`,
            assetFileNames: `assets/[name].[ext]`,
          },
        },
      },
      // Defines a build timestamp, intended for forcing reloads after a
      // deploy. Nothing in src/ reads __BUILD_TIME__, so it has no effect
      // until app code uses it.
      define: {
        __BUILD_TIME__: JSON.stringify(new Date().toISOString()),
      },
    })
  )
);
