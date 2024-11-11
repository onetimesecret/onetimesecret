//import { createHtmlPlugin } from 'vite-plugin-html'
import Vue from '@vitejs/plugin-vue';
import path from 'path';
import process from 'process';
import Markdown from 'unplugin-vue-markdown/vite';
import { defineConfig } from 'vite';

import { addTrailingNewline } from './src/build/plugins/addTrailingNewline';

// Remember, for security reasons, only variables prefixed with VITE_ are
// available here to prevent accidental exposure of sensitive
// environment variables to the client-side code.
const apiBaseUrl = process.env.VITE_API_BASE_URL || 'https://dev.onetimesecret.com';


export default defineConfig({
  root: "./src",
  plugins: [
    Vue({
      include: [/\.vue$/, /\.md$/], // <-- allows Vue to compile Markdown files
      template: {
        compilerOptions: {
          // Be cool and chill about 3rd party components. Alternatvely can use
          // `app.config.compilerOptions.isCustomElement = tag => tag.startsWith('altcha-')`
          // in main.ts.
          isCustomElement: tag => tag.includes('altcha-')

        }
      }
    }),

    // https://github.com/unplugin/unplugin-vue-markdown
    Markdown({ /* options */ }),

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
      '@': path.resolve(process.cwd(), './src'),

    }
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
        main: 'src/main.ts', // Explicitly define the entry point here
        //index: 'src/index.html'
      },
      //output: {
      //  manualChunks: undefined, // Disable code splitting
      //  entryFileNames: 'assets/[name].[hash].js', // Single JS file
      //  chunkFileNames: 'assets/[name].[hash].js', // Single JS file
      //  assetFileNames: 'assets/[name].[hash].[ext]', // Single CSS file
      //},

    },

    // https://guybedford.com/es-module-preloading-integrity
    // https://github.com/vitejs/vite/issues/5120#issuecomment-971952210
    modulePreload: {
      polyfill: true,
    },
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
    ]
  },

  define: {
    'process.env.API_BASE_URL': JSON.stringify(apiBaseUrl),
  },
})
