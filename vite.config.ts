// vite.config.ts

import VueI18nPlugin from '@intlify/unplugin-vue-i18n/vite';
import tailwindcss from '@tailwindcss/vite';
import Vue from '@vitejs/plugin-vue';
import { execSync } from 'child_process';
import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import process from 'process';
import Markdown from 'unplugin-vue-markdown/vite';
import { defineConfig, type PluginOption } from 'vite';

import { addTrailingNewline } from './src/build/plugins/addTrailingNewline';
import { checkCspChunkGraph } from './src/build/plugins/checkCspChunkGraph';
import { checkLocaleChunks } from './src/build/plugins/checkLocaleChunks';
import { DEBUG } from './src/utils/debug';

import VueDevTools from 'vite-plugin-vue-devtools';
import Inspector from 'vite-plugin-vue-inspector';

/**
 * Spotnote: optional, dev-only UI feedback for coding agents
 * ------------------------------------------------
 * Click an element on the dev server, write what should change, and the agent
 * gets its exact file, line and column. The plugin stamps
 * data-spotnote="file:line:col" on template elements and injects a picker
 * (launcher in the bottom-left corner). The plugin list below adds it only
 * for `vite` (serve), so `vite build` never runs it whatever the installed
 * version does; vitest.config.ts does not load this file.
 * https://github.com/harukikuri/spotnote
 *
 * It is a devDependency, loaded only when installed: a --prod install, or
 * removing the package, leaves this config working. Run with
 * NODE_ENV=development (the `vite` default) to see why it did not load.
 *
 * MCP server (optional, once per machine) so a local agent picks up notes as
 * you write them and can reply on them:
 *
 *   claude mcp add --scope user spotnote -- npx -y spotnote-mcp
 *   codex mcp add spotnote -- npx -y spotnote-mcp
 *
 * Then ask the agent: "Watch my Spotnote notes." The server listens on
 * 127.0.0.1:4848 only and saves notes in ~/.spotnote/. If the port is taken,
 * set SPOTNOTE_PORT to the same free port for the agent and for `pnpm dev`.
 * Without it, Enter copies the note as a prompt to paste instead.
 *
 * The backend proxies only /dist/* to Vite, so the picker's open-in-editor
 * links (GET /__spotnote/open) 404 when browsing through the Ruby app. Notes,
 * prompts and MCP are unaffected.
 */
const spotnote = await import('spotnote')
  .then((m) => {
    if (typeof m.default !== 'function') throw new TypeError('no default export');
    return m.default;
  })
  .catch((error: unknown) => {
    if (DEBUG) console.log(`[vite] Spotnote not loaded: ${String(error)}`);
    return null;
  });

// Remember, for security reasons, only variables prefixed with VITE_ are
// available here to prevent accidental exposure of sensitive
// environment variables to the client-side code.
const viteBaseUrl = process.env.VITE_BASE_URL;

/**
 * Sentry Release Version - Single Source of Truth
 * ------------------------------------------------
 * Determines the release version for both:
 * - Build-time injection into frontend bundle (__SENTRY_RELEASE__)
 * - Sentry sourcemap upload tagging
 *
 * Fallback chain:
 * 1. SENTRY_RELEASE env var (explicit override for CI/CD)
 * 2. .commit_hash.txt file (created by pre-commit hook, baked into Docker)
 * 3. git rev-parse (local development with git available)
 * 4. 'dev' (local development without git)
 *
 * Note: execSync is used here with a static command string (no user input),
 * which is safe for build-time git SHA retrieval.
 *
 * @see PR #2995 for backend release tracking
 */
function getSentryRelease(): string {
  // 1. Explicit environment variable takes precedence
  const envRelease = process.env.SENTRY_RELEASE;
  if (envRelease) {
    return envRelease;
  }

  // 2. Pre-generated commit hash file (Docker builds, CI artifacts)
  const commitHashPath = resolve(process.cwd(), '.commit_hash.txt');
  if (existsSync(commitHashPath)) {
    const hash = readFileSync(commitHashPath, 'utf-8').trim();
    if (hash) {
      return hash;
    }
  }

  // 3. Git SHA for local development (5s timeout prevents hanging builds)
  try {
    return execSync('git rev-parse --short=7 HEAD', { timeout: 5000 }).toString().trim();
  } catch {
    // 4. Final fallback for environments without git
    return 'dev';
  }
}

// server.allowedHosts - Multiple hosts can be separated by commas.
//
// https://vite.dev/config/server-options.html#server-allowedhosts
// https://github.com/vitejs/vite/security/advisories/GHSA-vg6x-rcgg-rjx6
const viteAdditionalServerAllowedHosts = process.env.VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS;

/**
 * Vite Configuration - Code-split build under a nonce-only CSP
 * ------------------------------------------------
 * One `vite build` pass emits both entries, main.ts (the customer bundle) and
 * admin.ts (the isolated Colonel console), as ES module chunks that share
 * code, plus one stylesheet and one manifest.
 *
 * CSP model: the production script-src is nonce-only (otto's
 * production_directives). The backend stamps the nonce on exactly one
 * <script type="module"> per shell (apps/web/core/views/helpers/vite_manifest.rb).
 * The chunks that script imports, statically or via import(), need no nonce
 * of their own: the HTML spec defines a script's cryptographic nonce as "The
 * cryptographic nonce metadata used for the initial fetch and for fetching any
 * imported modules", and CSP's script pre-request check allows a request whose
 * nonce metadata matches the policy. Two things do NOT inherit the nonce, and
 * the backend helper handles both: <link rel="modulepreload"> tags (each is
 * its own fetch, so the helper nonces the ones it emits) and the links Vite's
 * preload helper creates before a dynamic import (it reads the nonce from
 * <meta property="csp-nonce">, which the helper emits).
 *
 * Manifest Output Example (.vite/manifest.json):
 * {
 *   "main.ts": {
 *     "file": "assets/main.[hash].js",
 *     "isEntry": true,
 *     "imports": ["_vue-[hash].js", ...],
 *     "dynamicImports": ["apps/secret/support/Help.vue", ...]
 *   },
 *   "admin.ts": { ... },
 *   "_vue-[hash].js": { "file": "assets/vue-[hash].js", "imports": [...] },
 *   "style.css": {
 *     "file": "assets/style.[hash].css"
 *   }
 * }
 */

// eslint-disable-next-line max-lines-per-function
export default defineConfig(({ command }) => ({
  // Project root is ./src (imports resolve from here, index.html lives here)
  root: './src',

  plugins: [
    // Plugin order matters: Tailwind CSS first for stylesheet processing
    tailwindcss(),

    // Then Vue for component compilation
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

    /**
     * Vue I18n Plugin - Handles internationalization
     * ------------------------------------------------
     * Locales are pre-merged by Python script (locales/scripts/i18n content compile)
     * into single JSON files per locale in generated/locales/{locale}.json.
     * The src/i18n.ts module loads these pre-merged files directly.
     */
    VueI18nPlugin({
      // Disable automatic locale file discovery - we load pre-merged files
      // from generated/locales/ in src/i18n.ts
      include: [],

      // compositionOnly: true
      // - Only generates Composition API code (no Options API compatibility)
      // - Smaller bundle size, modern Vue 3 approach
      // - Requires using useI18n() instead of $t in <script>
      compositionOnly: true,

      // runtimeOnly: false
      // - Includes the full message compiler at runtime (not just pre-compiled)
      // - Allows dynamic message compilation and runtime template features
      // - Better Vue devtools support for inspecting translations
      // - Trade-off: ~8KB larger bundle vs. full runtime capabilities
      runtimeOnly: false,

      // fullInstall: true
      // - Includes all i18n APIs (datetime, number formatting, pluralization, etc.)
      // What fullInstall provides but you DON'T use:
      // - $d() / d() - datetime formatting (0 instances)
      // - $n() / n() - number formatting (0 instances)
      // - $tm() / tm() - translation message object access (0 instances)
      // - Advanced composition functions beyond t()
      // - Trade-off: Larger bundle vs. complete i18n functionality
      fullInstall: true,

      // strictMessage: true
      // - Enforces strict message format validation during compilation
      // - Special characters (@, {, }, etc.) must be properly escaped
      // - Catches syntax errors early at build time
      // - Prevents runtime message parsing failures
      // - Example: Use "email{'@'}example.com" not "email@example.com"
      strictMessage: true,

      // escapeHtml: true
      // - Automatically escapes HTML entities in translation strings
      // - Use v-html directive if intentional HTML formatting needed
      escapeHtml: true,

      // defaultSFCLang: 'json'
      // - Default language format for Single File Component i18n blocks
      // - Specifies that <i18n> blocks in .vue files use JSON format
      // - Alternatives: 'yaml', 'json5', 'yml'
      defaultSFCLang: 'json',
    }),

    // Enable Vue Devtools
    VueDevTools({ launchEditor: 'zed' }),
    Inspector(),

    // Optional dev-only element picker for coding agents; see the note above.
    command === 'serve' ? spotnote?.() : null,

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

    // Fails the build if configureZod.ts leaves the zod chunk or an entry
    // stops importing that chunk statically (the advancedChunks group below
    // and the CSP note at the top of this file).
    checkCspChunkGraph(),

    // Fails the build if a locale other than en.json ends up in an entry
    // chunk or in a chunk an entry imports statically, or if one chunk has
    // more than one locale. src/i18n.ts loads every other locale on demand.
    checkLocaleChunks(),
    // Note: Sentry sourcemaps are uploaded via CI (sentry-cli), not at build time.
    // This keeps auth tokens out of the build context. See .github/workflows/build-and-publish-oci-images.yml
  ].filter(Boolean) as PluginOption[],

  resolve: {
    alias: {
      '@': resolve(process.cwd(), './src'),
      '@tests': resolve(process.cwd(), './tests'),
      '@generated': resolve(process.cwd(), './generated'),
      // vue: 'vue/dist/vue.runtime.esm-bundler.js',
    },
  },

  assetsInclude: ['assets/fonts/**/*.woff', 'assets/fonts/**/*.woff2'], // Include font files
  base: '/dist',

  publicDir: 'public/web',

  // be simpler and more efficient.
  build: {
    minify: true,
    outDir: '../public/web/dist',

    // It's important in staging to keep the previous files around during and
    // for an hour after fly deploy: during the deploy so that requests coming
    // in going to one or the other machines can continue serving the previous
    // version, and for an hour after the deploy for the redis cache to expire
    // (or be manually deleted). The key is template:global:vite_assets in db 0.
    //
    // outDir is outside root (src/), so Vite only empties it when told to.
    emptyOutDir: true,

    // One manifest for both entries. The backend resolves an entry's chunk,
    // its static imports (for modulepreload) and the stylesheet from it.
    manifest: true,
    rolldownOptions: {
      input: {
        main: 'main.ts', // customer bundle
        admin: 'admin.ts', // isolated Colonel admin console
      },
      output: {
        // Chunks shared between the entries, and one chunk per lazy route.
        // See the CSP note at the top of this file for why chunks need no
        // nonce of their own.
        codeSplitting: true,
        format: 'es',
        // Entries are `name.hash.js`, shared and lazy chunks `name-hash.js`,
        // so a glob on main.*.js or admin.*.js only ever matches an entry
        // (.github/scripts/sentry-sourcemap-preflight.sh relies on that).
        entryFileNames: 'assets/[name].[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name].[hash].[ext]',
        preserveModules: false,
        // Keep src/plugins/core/configureZod.ts in the same chunk as zod.
        // Every schema module imports zod, so that chunk, and with it
        // `z.config({ jitless: true })`, evaluates before any schema is built.
        // Left to the default chunking, configureZod ended up in a chunk that
        // ran after the first schemas, and Zod's `new Function("")` probe
        // tripped a script-src violation on every page load.
        advancedChunks: {
          groups: [
            {
              name: 'zod',
              test: (id: string) =>
                id.includes('/node_modules/zod/') ||
                id.endsWith('/src/plugins/core/configureZod.ts'),
            },
          ],
        },
        // Rolldown native minification options (replaces terserOptions).
        // Terser is incompatible with Rolldown's output format and produces
        // "undefined is not a function" at runtime.
        minify: {
          compress: {
            dropConsole: true,
            dropDebugger: true,
          },
          mangle: true,
        },
      },
    },

    // One stylesheet for both shells, linked from the manifest's style.css
    // entry; the admin console shares the customer styles plus its own.
    cssCodeSplit: false,
    sourcemap: true,
    // Up from the default 500 KB: the customer entry carries the English
    // messages (src/i18n.ts bundles en; every other locale is its own chunk,
    // the largest under 400 KB) and is just over 500 KB.
    chunkSizeWarningLimit: 600,
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
    // HMR must use the same host as the browser to avoid WebSocket connection failures.
    // When the browser is at dev.onetime.dev but HMR tries localhost:5173, the connection
    // fails and can cause components to re-mount outside the Vue app context.
    hmr: viteBaseUrl
      ? {
          host: new URL(viteBaseUrl).hostname,
          protocol: 'wss',
        }
      : true,
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
    // vue-i18n (intlify) feature flags — Rollup auto-replaced these but
    // Rolldown requires explicit definition to avoid ReferenceError at runtime
    __INTLIFY_PROD_DEVTOOLS__: false,
    // Sentry release version baked at build time to match sourcemap uploads.
    // Falls back to 'dev' when .commit_hash.txt doesn't exist (local development).
    __SENTRY_RELEASE__: JSON.stringify(getSentryRelease()),
  },
}));
