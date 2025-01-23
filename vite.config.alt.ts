//import { createHtmlPlugin } from 'vite-plugin-html'
import Vue from '@vitejs/plugin-vue';
import { resolve } from 'path';
import process from 'process';
import Markdown from 'unplugin-vue-markdown/vite';
import { defineConfig } from 'vite';
//import checker from 'vite-plugin-checker';
//import vueDevTools from 'vite-plugin-vue-devtools';
//import Inspector from 'vite-plugin-vue-inspector'; // OR vite-plugin-vue-inspector
import { DEBUG } from './src/utils/debug';

import { addTrailingNewline } from './src/build/plugins/addTrailingNewline';

// Remember, for security reasons, only variables prefixed with VITE_ are
// available here to prevent accidental exposure of sensitive
// environment variables to the client-side code.
const apiBaseUrl = process.env.VITE_API_BASE_URL;

/**
 * Alternative Vite Configuration - Consolidated Assets
 * ------------------------------------------------
 * This configuration consolidates assets for simpler CSP management:
 * - Single JS bundle (no code splitting)
 * - Separate style.css entry
 * - Simplified manifest format
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
 * Key Differences:
 * - Uses inlineDynamicImports for single JS bundle
 * - Explicit style.css entry
 * - Simpler asset preloading for CSP headers
 */
export default defineConfig({
  // Sets project root to ./src directory
  // - All imports will be resolved relative to ./src
  // - Static assets should be placed in ./src/public
  // - Index.html should be in ./src
  root: './src',
  // If root is NOT set:
  // - Project root will be the directory with vite.config.ts
  // - Static assets go in ./public
  // - Index.html should be in project root
  plugins: [
    // re: order of plugins
    // - Vue plugin should be early in the chain
    // - Transformation/checking plugins follow framework plugins
    // - Plugins that modify code should precede diagnostic plugins
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
        compilerOptions: {
          // Be cool and chill about 3rd party components. Alternatvely can use
          // `app.config.compilerOptions.isCustomElement = tag => tag.startsWith('altcha-')`
          // in main.ts.
          isCustomElement: (tag) => tag.includes('altcha-'),
        },
      },
    }),

    // // Enable type checking and linting w/o blocking hmr
    // checker({
    //   typescript: true,
    //   vueTsc: true,
    // }),

    // Enable Vue Devtools
    //vueDevTools(),
    //Inspector(),

    // https://github.com/unplugin/unplugin-vue-markdown
    Markdown({
      /* options */
    }),

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
    outDir: '../public/web/dist',

    // It's important in staging to keep the previous files around during and
    // for an hour after fly deploy: during the deploy so that requests coming
    // in going to one or the other machines can continue serving the previous
    // version, and for an hour after the deploy for the redis cache to expire
    // (or be manually deleted). The key is template:global:vite_assets in db 0.
    emptyOutDir: true,

    // Code Splitting vs Combined Files
    //
    // Code Splitting:
    // Advantages:
    // 1. Improved Initial Load Time: Only the necessary code for the initial page
    // is loaded, with additional code loaded as needed.
    // 2. Better Caching: Smaller, more granular files can be cached more
    // effectively. Changes in one part of the application only require updating
    // the corresponding file.
    // 3. Parallel Loading: Modern browsers can download multiple files in
    // parallel, speeding up the overall loading process.
    //
    // Disadvantages:
    // 1. Increased Complexity: Managing multiple files can be more complex,
    // especially with dependencies and ensuring correct load order.
    // 2. More HTTP Requests: More files mean more HTTP requests, which can be a
    // performance bottleneck on slower networks.
    //
    // Combined Files:
    // Advantages:
    // 1. Simplicity: A single file is easier to manage and deploy, with no
    // concerns about missing files or incorrect load orders.
    // 2. Fewer HTTP Requests: Combining everything into a single file reduces the
    // number of HTTP requests, beneficial for performance on slower networks.
    //
    // Disadvantages:
    // 1. Longer Initial Load Time: The entire application needs to be downloaded
    // before it can be used, increasing initial load time.
    // 2. Inefficient Caching: Any change in the application requires the entire
    // bundle to be re-downloaded.
    //
    // Conclusion:
    // The conventional approach in modern web development is to use code
    // splitting for better performance and caching. However, the best approach
    // depends on the specific use case. For larger applications, code splitting
    // is usually preferred, while for smaller applications, combining files might
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

    // https://guybedford.com/es-module-preloading-integrity
    // https://github.com/vitejs/vite/issues/5120#issuecomment-971952210
    // modulepreload: true,

    cssCodeSplit: false,
    sourcemap: true,
  },

  server: {
    origin: apiBaseUrl,
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
    'process.env.API_BASE_URL': JSON.stringify(apiBaseUrl),
    __VUE_PROD_DEVTOOLS__: DEBUG,
  },
});
