import { defineConfig } from 'vite'
import { createHtmlPlugin } from 'vite-plugin-html'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  root: "./src",

  plugins: [
    vue({
      template:{
        compilerOptions: {

        }
      }
    }),
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
    //        '/v3/dist/assets/ZillaSlab-Regular.woff2',
    //        '/v3/dist/assets/ZillaSlab-Regular.woff',
    //        '/v3/dist/assets/ZillaSlab-Bold.woff2',
    //        '/v3/dist/assets/ZillaSlab-Bold.woff',
    //      ]
    //    }
    //  }
    //})
  ],

  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src')
    }
  },

  assetsInclude: ['**/*.woff', '**/*.woff2'], // Include font files
  base: '/v3/dist/',
  build: {
    outDir: '../public/web/v3/dist',
    emptyOutDir: true,

    manifest: true,
    rollupOptions: {
      input: 'src/main.ts',
    },

    // https://guybedford.com/es-module-preloading-integrity
    // https://github.com/vitejs/vite/issues/5120#issuecomment-971952210
    modulePreload: {
      polyfill: true,
    },
  },



  server: {
    origin: 'https://dev.onetimesecret.com',
  },
})
