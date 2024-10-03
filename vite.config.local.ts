import { defineConfig, mergeConfig } from 'vite'
import baseConfig from './vite.config.ts';

/**
 * Local Vite Configuration
 *
 * This configuration is specifically designed for local builds of the Vue app.
 * It allows the frontend to be run directly from the git repository without
 * requiring the installation of the entire JavaScript development environment.
 *
 * Purpose:
 * 1. Simplify deployment in environments where setting up a full JS dev stack
 *    is impractical.
 * 2. Enable quick testing and running of the frontend from the git repo.
 * 3. Facilitate easier integration with backend systems that may not have
 *    Node.js installed.
 *
 * Key Features:
 * - Merges with the base Vite configuration to maintain core settings.
 * - Customizes the output file naming to create a more predictable and flat
 *   structure.
 *
 * Usage:
 * To run a local build, use the following command:
 *   pnpm run build:local
 *
 * This command runs type-checking and then builds the project using this local
 * configuration.
 *
 * The generated files from this build can and should be checked into version
 * control. This allows the built frontend to be immediately usable from the git
 * repository, without requiring additional build steps on the deployment
 * target.
 *
 * Output:
 * The build process will generate files in the `public/web/dist/` directory
 * (or as configured). These files should be committed to the repository for
 * direct use.
 */
export default mergeConfig(baseConfig, defineConfig({
  build: {
    rollupOptions: {
      output: {
        // Generate predictable filenames without hashes for easier referencing
        entryFileNames: `assets/[name].js`,
        chunkFileNames: `assets/[name].js`,
        assetFileNames: `assets/[name].[ext]`
      },
    },
  }
}));
