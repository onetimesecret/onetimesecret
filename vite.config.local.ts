// vite.config.local.ts

import process from 'process';
import { defineConfig, mergeConfig } from 'vite';
import baseConfig from './vite.config';

/**
 * Local Vite Configuration
 *
 * Builds the same bundles as `vite.config.ts`, but with predictable file
 * names instead of content hashes (e.g. `assets/main.js`). Everything else,
 * including minification, single-chunk output and the ES module format that
 * matches the backend's `<script type="module">` tag, comes from the base
 * config. The backend resolves files through the Vite manifests
 * (apps/web/core/views/helpers/vite_manifest.rb), so it serves either build
 * without changes.
 *
 * Differences from the base config:
 * - File names without content hashes
 * - `__BUILD_TIME__` defined as the ISO timestamp of the build
 *
 * Usage:
 * Run `pnpm run build:local`. Like `pnpm run build`, it runs two passes: the
 * customer bundle (main.ts), then the admin console (admin.ts, selected by
 * VITE_BUILD_TARGET=admin). The output is written to `public/web/dist`,
 * which is gitignored, so it is not committed.
 *
 * Note: the base config is a callback (`defineConfig(env => ...)`), and
 * Vite's `mergeConfig` refuses callbacks, so this config is a callback too
 * and resolves the base with the same env before merging.
 *
 */
const isAdminBuild = process.env.VITE_BUILD_TARGET === 'admin';

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
            // Both passes emit a style.css with different contents into the
            // same dist. Without a hash the admin pass would overwrite the
            // customer stylesheet, so its CSS gets an admin- prefix.
            assetFileNames: ({ names }) =>
              isAdminBuild && names.some((name) => name.endsWith('.css'))
                ? `assets/admin-[name].[ext]`
                : `assets/[name].[ext]`,
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
