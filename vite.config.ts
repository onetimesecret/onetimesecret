// vite.config.ts

import Vue from '@vitejs/plugin-vue';
import { resolve } from 'path';
import process from 'process';
import Markdown from 'unplugin-vue-markdown/vite';
import { defineConfig } from 'vite';
import { visualizer } from 'rollup-plugin-visualizer';

import { addTrailingNewline } from './src/build/plugins/addTrailingNewline';
import { DEBUG } from './src/utils/debug';

//import { createHtmlPlugin } from 'vite-plugin-html'
//import checker from 'vite-plugin-checker';
import vueDevTools from 'vite-plugin-vue-devtools';
import Inspector from 'vite-plugin-vue-inspector'; // OR vite-plugin-vue-inspector

// Remember, for security reasons, only variables prefixed with VITE_ are
// available here to prevent accidental exposure of sensitive
// environment variables to the client-side code.
const viteBaseUrl = process.env.VITE_BASE_URL;

// According to the documentation, we should be able to set the allowed hosts
// via __VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS but as of 5.4.15, that is not
// working as expected. So here we capture the value of that env var with
// and without the __ prefix and if either are defined, add the hosts to
// server.allowedHosts below. Multiple hosts can be separated by commas.
//
// https://vite.dev/config/server-options.html#server-allowedhosts
// https://github.com/vitejs/vite/security/advisories/GHSA-vg6x-rcgg-rjx6
const viteAdditionalServerAllowedHosts =
  process.env.__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS ??
  process.env.VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS;

/**
 * Vite Configuration - Consolidated Assets
 * ------------------------------------------------
 * This configuration consolidates assets for simpler CSP management:
 * - Single JS bundle (no code splitting)
 * - Separate style.css entry
 * - Simplified manifest format
 *
 * The single-bundle approach enables strict Content Security Policy (CSP)
 * implementation with nonces, as each script chunk would otherwise require
 * its own unique nonce attribute.
 *
 * Manifest Output Example:
 * {
 *   "main.ts": {
 *     "file": "assets/main.[hash].js",
 *     "isEntry": true
 *   },
 *   "style.css": {
 *     "file": "assets/style.[hash].css"
 *   }
 * }
 *
 * @see 29ffd790d74599bbbe3755d0fcba2b59c2f59ed7
 */
export default defineConfig({
  // Project root is ./src (imports resolve from here, index.html lives here)
  root: './src',

  plugins: [
    // Plugin order matters: Vue first, then transformations, then diagnostics
    Vue({
      include: [/\.vue$/, /\.md$/], // <-- allows Vue to compile Markdown files
      template: {
        /**
         * RABBIT HOLE AVOIDANCE: Vue Runtime Compiler Warning
         * --------------------------------------------------------
         * In the browser console, you may see the following warning:
         * "[Vue warn]: The `compilerOptions` config option is only respected when using a build
         *  of Vue.js that includes the runtime compiler (aka "full build")..."
         *
         * when _any_ code reads app.config.compilerOptions at runtime. This includes:
         * - Direct access in application code
         * - Indirect access via Vue Devtools (confirmed source via stack trace)
         * - Pinia devtools integration
         *
         * This warning is _expected_ in development and can be safely ignored. It occurs bc
         * Vue's runtime-only build (default in Vite) doesn't include the compiler.
         *
         * To debug if warning source is unclear:
         * 1. In browser console:
         *    debug(console.warn, (args) => args[0].includes('compilerOptions'))
         * 2. Check stack trace for Pinia/Devtools initialization
         *
         * To verify this is dev-only, run `npm run build &&  npm run preview`
         * The warning should not appear in the production build.
         *
         * Reference: Discovered via stack trace to Pinia devtools initialization:
         * $subscribe @ pinia.js -> devtoolsInitApp @ chunk-LR5MW2GB.js -> mount
         */
        compilerOptions: {},
      },
    }),

    visualizer({
      filename: '../public/web/dist/stats.html',
      open: false,
      gzipSize: true,
      brotliSize: true,
      template: 'treemap',
    }),

    // Enable Vue Devtools
    vueDevTools(),
    Inspector(),

    // https://github.com/unplugin/unplugin-vue-markdown
    Markdown({}),

    /**
     * Makes sure all text output files have a trailing newline.
     *
     * After running the build, some files like manifest.json
     * and main.map are generated with a trailing last line. Not
     * a big deal really, just that it triggers standard lint
     * rules. I wouldn't think this is necessary but here we are.
     *
     * This plugin processes files during the build phase:
     * - Checks each generated file for a trailing newline.
     * - Adds a newline if it's missing.
     * - Ignores binary files to avoid corruption.
     *
     * @see ./src/build/plugins/addTrailingNewline.ts for implementation details.
     */
    addTrailingNewline(),
  ],

  resolve: {
    alias: {
      '@': resolve(process.cwd(), './src'),
      '@tests': resolve(process.cwd(), './tests'),
      // vue: 'vue/dist/vue.runtime.esm-bundler.js',
    },
  },

  assetsInclude: ['assets/fonts/**/*.woff', 'assets/fonts/**/*.woff2'], // Include font files
  base: '/dist',

  publicDir: 'public/web',

  // be simpler and more efficient.
  build: {
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true,
        passes: 2, // Number of compression passes
      },
    },
    outDir: '../public/web/dist',

    // It's important in staging to keep the previous files around during and
    // for an hour after fly deploy: during the deploy so that requests coming
    // in going to one or the other machines can continue serving the previous
    // version, and for an hour after the deploy for the redis cache to expire
    // (or be manually deleted). The key is template:global:vite_assets in db 0.
    emptyOutDir: true,

    // Single Bundle Strategy
    //
    // We intentionally disable code splitting to support CSP nonces.
    // While this increases initial load time, it simplifies nonce
    // management by requiring only one script tag. Code splitting would
    // require generating and tracking nonces for each chunk, adding
    // complexity without significant benefit for our use case.
    manifest: true,
    rollupOptions: {
      input: {
        main: 'src/main.ts',
      },
      output: {
        // Enforce single chunk output
        inlineDynamicImports: true,
        format: 'es',
        entryFileNames: 'assets/[name].[hash].js',
        assetFileNames: 'assets/[name].[hash].[ext]',
        // Prevent dynamic imports
        preserveModules: false,
      },
    },

    cssCodeSplit: false,
    sourcemap: true,
    chunkSizeWarningLimit: 3000, // up from default 500 KB to accommodate single bundle
  },

  css: {
    // Helps debugging in dev. No effect on builds.
    devSourcemap: true,
  },

  /**
   * Server Security Configuration: allowedHosts
   * ------------------------------------------
   * This security feature was added in Vite 5.4.12 to address vulnerability GHSA-vg6x-rcgg-rjx6,
   * which allowed unauthorized websites to send requests to the Vite dev server.
   *
   * By default, Vite only allows requests from 'localhost' and '127.0.0.1'.
   * For specific domains (like 'dev.onetime.dev'), they must be explicitly allowed.
   *
   * We handle both env vars with and without "__" prefix since the documentation
   * references different formats, and this implementation ensures future compatibility.
   *
   * Security note: Never set allowedHosts: true in production as this allows any origin
   * to access your dev server.
   *
   * @see https://vitejs.dev/config/server-options.html#server-allowedhosts
   * @see https://github.com/vitejs/vite/security/advisories/GHSA-vg6x-rcgg-rjx6
   */
  server: {
    origin: viteBaseUrl,
    allowedHosts: (() => {
      // NOTE: This is an Immediately Invoked Function Expression (IIFE)
      // that executes exactly once during config load/parsing time.
      // The returned array becomes the value of allowedHosts. We do
      // this to avoid adding empty strings to the array.
      //
      // Start with default allowed hosts
      const hosts = ['localhost', '127.0.0.1'];

      // Add additional hosts from environment variables if defined
      if (viteAdditionalServerAllowedHosts) {
        // Split by comma and add each host to the array
        const additionalHosts = viteAdditionalServerAllowedHosts
          .split(',')
          .map((host) => host.trim());
        hosts.push(...additionalHosts.filter((host) => host !== ''));
      }

      // Log all the allowed hosts for debugging
      if (DEBUG) {
        const timestamp = new Date().toLocaleTimeString();
        console.log(`${timestamp} [vite] Vite server allowed hosts:`, hosts);
      }

      return hosts;
    })(),
  },

  // Add this section to explicitly include dependencies for pre-bundling
  optimizeDeps: {
    include: [
      // List dependencies that you want to pre-bundle here
      // Example: 'vue', 'axios'
      'vue',
      'vue-router',
      'axios',
    ],
  },

  define: {
    'process.env.VITE_BASE_URL': JSON.stringify(viteBaseUrl),
    'process.env.VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS': JSON.stringify(
      viteAdditionalServerAllowedHosts
    ),
    __VUE_PROD_DEVTOOLS__: DEBUG,
  },
});
