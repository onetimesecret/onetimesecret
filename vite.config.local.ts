import { defineConfig, mergeConfig } from 'vite';
import baseConfig from './vite.config';

/**
 * Local Vite Configuration
 *
 * This configuration is optimized for generating builds that can be
 * easily checked into version control and run without a full JS
 * development environment.
 *
 * Purpose:
 * - Simplify deployment in environments where setting up a full JS dev
 *   stack is impractical.
 * - Enable quick testing and running of the frontend from the git repo.
 * - Facilitate easier integration with backend systems that may not
 *   have Node.js installed.
 *
 * Key features:
 * - Predictable file naming without content hashes
 * - Sourcemaps for easier debugging
 * - Disabled minification for better readability
 * - Single bundle output (no code splitting) for simpler deployment
 * - Build timestamp for cache busting
 *
 * Usage:
 * Run `pnpm run build:local` to generate the build.
 * The output will be in the `public/web/dist` directory.
 * These files should be committed to the repository.
 *
 */
export default mergeConfig(
  baseConfig,
  defineConfig({
    build: {
      // Generate sourcemaps for easier debugging
      sourcemap: true,
      rollupOptions: {
        output: {
          // Generate predictable filenames without hashes
          entryFileNames: `assets/[name].js`,
          chunkFileNames: `assets/[name].js`,
          assetFileNames: `assets/[name].[ext]`,
          // Ensure exports are named for easier integration
          format: 'umd',
        },
      },
    },
    // Defines a build timestamp that can be used in the app
    // to force reloads when a new version is deployed.
    define: {
      __BUILD_TIME__: JSON.stringify(new Date().toISOString()),
    },
  })
);
