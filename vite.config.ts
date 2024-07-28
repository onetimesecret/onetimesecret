import { defineConfig } from 'vite'
import { createHtmlPlugin } from 'vite-plugin-html'
import vue from '@vitejs/plugin-vue'
import path from 'path'

// Remember, for security reasons, only variables prefixed with VITE_ are
// available here to prevent accidental exposure of sensitive
// environment variables to the client-side code.
const apiBaseUrl = process.env.VITE_API_BASE_URL || 'https://dev.onetimesecret.com';

export default defineConfig({
  root: "./src",

  plugins: [
    vue({
      template:{
        compilerOptions: {

        }
      }
    }),
    // Uncomment and adjust the createHtmlPlugin configuration as needed
    // TODO: Doesn't add the preload <link> to the output index.html
    //       but it does process the html b/c minify: true works.
    //       Might be handy for some use cases. Leaving for now.
    // Corresponds with the following in the input index.html:
    //
    //  <%~ preloadFonts.map(font => `<link rel="preload" href="${font}" as="font" type="font/woff2">`) %>
    //
    //createHtmlPlugin({
    //  minify: false,
    //  entry: 'main.ts',
    //  template: 'index.html',
    //  inject: {
    //    data: {
    //      preloadFonts: [
    //        '/dist/assets/ZillaSlab-Regular.woff2',
    //        '/dist/assets/ZillaSlab-Regular.woff',
    //        '/dist/assets/ZillaSlab-Bold.woff2',
    //        '/dist/assets/ZillaSlab-Bold.woff',
    //      ]
    //    }
    //  }
    //})
  ],

  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),

      // Resolves browser console warning:
      //
      //    [Vue warn]: Component provided template option but runtime compilation is
      //    not supported in this build of Vue. Configure your bundler to alias "vue"
      //    to "vue/dist/vue.esm-bundler.js".
      //
      'vue': 'vue/dist/vue.esm-bundler.js'
    }
  },

  assetsInclude: ['**/*.woff', '**/*.woff2'], // Include font files
  base: '/dist/',
  build: {
    outDir: '../public/web/dist',
    emptyOutDir: true,

    manifest: true,
    rollupOptions: {
      input: 'src/main.ts', // Explicitly define the entry point here
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
      //'vue'
    ]
  },

  define: {
    'process.env.API_BASE_URL': JSON.stringify(apiBaseUrl),
  },
})
