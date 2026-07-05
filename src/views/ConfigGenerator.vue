<!-- src/views/ConfigGenerator.vue -->
<!--
  Configuration Generator — a static, public tool that turns a handful of
  preset choices into ready-to-use etc/config.yaml / etc/auth.yaml override
  fragments plus a companion .env snippet. No database, no session, no config
  mutation: it only ever reads the pure JSON endpoints backed by
  Onetime::ConfigGenerator (apps/web/core/controllers/config_generator.rb).

  UX inspiration: the Caddy download/config builder and Fly.io's first-deploy
  picker — choose options in the browser, copy the result, continue on the
  command line. The current selections are mirrored into the URL query string,
  so a configured link is shareable and bookmarkable.

  The same /config-generator/render endpoint returns JSON, so a future
  install.sh could pre-seed a config from a chosen link (see
  docs/specs/config-generator.md). Uses plain fetch() with relative,
  same-origin URLs so the page stays self-contained.
-->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useTheme } from '@/shared/composables/useTheme';
  import { yaml } from '@codemirror/lang-yaml';
  import { EditorState } from '@codemirror/state';
  import { oneDark } from '@codemirror/theme-one-dark';
  import { EditorView } from '@codemirror/view';
  import { basicSetup } from 'codemirror';
  import { computed, onMounted, reactive, ref, watch } from 'vue';
  import CodeMirror from 'vue-codemirror6';
  import { useRoute, useRouter } from 'vue-router';

  type OptionChoice = { value: string | number; label: string };

  interface OptionSpec {
    label: string;
    description?: string;
    type: 'select' | 'boolean';
    default: string | number | boolean;
    choices?: OptionChoice[];
    requires?: Record<string, string | number | boolean>;
  }

  type OptionsCatalog = Record<string, OptionSpec>;

  interface RenderResponse {
    config_yaml: string;
    auth_yaml: string;
    env_snippet: string;
    selections: Record<string, string | number | boolean>;
    warnings: string[];
  }

  const route = useRoute();
  const router = useRouter();
  const { isDarkMode } = useTheme();

  const catalog = ref<OptionsCatalog>({});
  const selections = reactive<Record<string, string | number | boolean>>({});
  const rendered = ref<RenderResponse | null>(null);
  const loadError = ref<string | null>(null);
  const isLoading = ref(true);

  const outputs = [
    { key: 'config_yaml' as const, label: 'config.yaml', filename: 'config.yaml', lang: 'yaml' },
    { key: 'auth_yaml' as const, label: 'auth.yaml', filename: 'auth.yaml', lang: 'yaml' },
    { key: 'env_snippet' as const, label: '.env', filename: '.env', lang: 'ini' },
  ];
  const activeOutput = ref<(typeof outputs)[number]['key']>('config_yaml');
  const copied = ref(false);

  // A dependent option (e.g. sso_enabled requires deployment_mode: full) is
  // rendered but disabled until its requirement is met; the backend applies
  // the same rule and warns if a stale value slips through.
  function requirementMet(spec: OptionSpec): boolean {
    if (!spec.requires) return true;
    return Object.entries(spec.requires).every(([dep, val]) => selections[dep] === val);
  }

  function requirementHint(spec: OptionSpec): string {
    if (!spec.requires) return '';
    return Object.entries(spec.requires)
      .map(([dep, val]) => `${catalog.value[dep]?.label ?? dep}: ${val}`)
      .join(', ');
  }

  // Seed a selection from the URL query (?deployment_mode=full&...) when
  // present and valid, otherwise from the option's default. This is what
  // makes a shared/bookmarked link reproduce the same configuration.
  function seedSelections(cat: OptionsCatalog) {
    for (const [key, spec] of Object.entries(cat)) {
      const raw = route.query[key];
      if (raw == null) {
        selections[key] = spec.default;
        continue;
      }
      const value = Array.isArray(raw) ? raw[0] : raw;
      if (spec.type === 'boolean') {
        selections[key] = value === 'true';
      } else if (spec.choices?.some((c) => String(c.value) === String(value))) {
        selections[key] = coerceChoice(spec, value as string);
      } else {
        selections[key] = spec.default;
      }
    }
  }

  function coerceChoice(spec: OptionSpec, value: string): string | number {
    const match = spec.choices?.find((c) => String(c.value) === String(value));
    return match ? match.value as string | number : (spec.default as string | number);
  }

  function toQuery(): Record<string, string> {
    const query: Record<string, string> = {};
    for (const [key, value] of Object.entries(selections)) {
      const spec = catalog.value[key];
      if (!spec) continue;
      // Only carry non-default values so shared links stay short and legible.
      if (value === spec.default) continue;
      query[key] = String(value);
    }
    return query;
  }

  async function fetchCatalog() {
    const res = await fetch('/config-generator/options', {
      headers: { Accept: 'application/json' },
    });
    if (!res.ok) throw new Error(`options request failed (${res.status})`);
    const data = await res.json();
    return data.options as OptionsCatalog;
  }

  async function fetchRender() {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(selections)) {
      params.set(key, String(value));
    }
    const res = await fetch(`/config-generator/render?${params.toString()}`, {
      headers: { Accept: 'application/json' },
    });
    if (!res.ok) throw new Error(`render request failed (${res.status})`);
    rendered.value = (await res.json()) as RenderResponse;
  }

  let renderTimer: ReturnType<typeof setTimeout> | undefined;
  function scheduleRender() {
    if (renderTimer) clearTimeout(renderTimer);
    renderTimer = setTimeout(() => {
      fetchRender().catch((err) => {
        loadError.value = err instanceof Error ? err.message : String(err);
      });
      // Keep the URL in sync so the current configuration is always shareable.
      router.replace({ query: toQuery() }).catch(() => {
        /* duplicated navigation is fine */
      });
    }, 250);
  }

  onMounted(async () => {
    try {
      const cat = await fetchCatalog();
      catalog.value = cat;
      seedSelections(cat);
      await fetchRender();
    } catch (err) {
      loadError.value = err instanceof Error ? err.message : String(err);
    } finally {
      isLoading.value = false;
    }
  });

  watch(selections, scheduleRender, { deep: true });

  // ── Preview pane (read-only CodeMirror, one instance, content swaps by tab) ──
  const lang = computed(() => yaml());
  const extensions = computed(() => [
    basicSetup,
    isDarkMode.value ? oneDark : EditorView.theme({}),
    EditorState.readOnly.of(true),
    EditorView.editable.of(false),
    EditorView.lineWrapping,
    EditorView.theme({
      '&.cm-editor.cm-focused': { outline: 'none' },
      '.cm-content': { caretColor: 'transparent' },
    }),
  ]);

  const activeContent = computed(() => (rendered.value ? rendered.value[activeOutput.value] : ''));
  const activeOutputMeta = computed(
    () => outputs.find((o) => o.key === activeOutput.value) ?? outputs[0]
  );

  async function copyActive() {
    try {
      await navigator.clipboard.writeText(activeContent.value);
      copied.value = true;
      setTimeout(() => (copied.value = false), 1500);
    } catch {
      /* clipboard unavailable (insecure context) — user can still select text */
    }
  }

  function downloadActive() {
    const meta = activeOutputMeta.value;
    const blob = new Blob([activeContent.value], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = meta.filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  const warnings = computed(() => rendered.value?.warnings ?? []);
</script>

<template>
  <div class="container mx-auto max-w-6xl px-4 py-8">
    <header class="mb-8">
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
        Configuration Generator
      </h1>
      <p class="mt-2 max-w-2xl text-sm text-gray-600 dark:text-gray-400">
        Pick a few preset options and copy the resulting YAML into
        <code class="rounded bg-gray-100 px-1 dark:bg-gray-800">etc/config.yaml</code> and
        <code class="rounded bg-gray-100 px-1 dark:bg-gray-800">etc/auth.yaml</code>. These files
        layer on top of the shipped defaults, so you only need the keys you want to change. See the
        <a
          href="https://docs.onetimesecret.com/en/self-hosting/configuration/"
          class="text-brand-600 underline dark:text-brand-400"
          target="_blank"
          rel="noopener">configuration reference</a>
        for the full option surface.
      </p>
    </header>

    <div
      v-if="isLoading"
      class="p-6 text-center text-gray-500 dark:text-gray-400">
      Loading options…
    </div>

    <div
      v-else-if="loadError"
      class="rounded-md border border-red-400 bg-red-50 p-4 text-red-700 dark:bg-red-900/40 dark:text-red-200">
      <p class="font-medium">
        Could not load the configuration generator.
      </p>
      <p class="mt-1 text-sm">
        {{ loadError }}
      </p>
    </div>

    <div
      v-else
      class="grid gap-8 lg:grid-cols-2">
      <!-- ── Options ── -->
      <section aria-label="Configuration options">
        <div class="space-y-5">
          <div
            v-for="(spec, key) in catalog"
            :key="key"
            class="rounded-lg border border-gray-200 p-4 dark:border-gray-700">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <label
                  :for="`opt-${key}`"
                  class="block text-sm font-medium text-gray-900 dark:text-white">
                  {{ spec.label }}
                </label>
                <p
                  v-if="spec.description"
                  class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                  {{ spec.description }}
                </p>
                <p
                  v-if="spec.requires && !requirementMet(spec)"
                  class="mt-1 text-xs text-amber-600 italic dark:text-amber-400">
                  Requires {{ requirementHint(spec) }}
                </p>
              </div>

              <!-- Boolean toggle -->
              <div
                v-if="spec.type === 'boolean'"
                class="shrink-0 pt-1">
                <button
                  :id="`opt-${key}`"
                  type="button"
                  role="switch"
                  :aria-checked="selections[key] === true"
                  :disabled="!requirementMet(spec)"
                  @click="selections[key] = !selections[key]"
                  class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-40"
                  :class="selections[key] ? 'bg-brand-500' : 'bg-gray-300 dark:bg-gray-600'">
                  <span
                    class="inline-block size-4 rounded-full bg-white transition-transform"
                    :class="selections[key] ? 'translate-x-6' : 'translate-x-1'"></span>
                </button>
              </div>
            </div>

            <!-- Select -->
            <div
              v-if="spec.type === 'select'"
              class="mt-3">
              <select
                :id="`opt-${key}`"
                v-model="selections[key]"
                class="block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-white">
                <option
                  v-for="choice in spec.choices"
                  :key="String(choice.value)"
                  :value="choice.value">
                  {{ choice.label }}
                </option>
              </select>
            </div>
          </div>
        </div>
      </section>

      <!-- ── Output ── -->
      <section aria-label="Generated configuration">
        <!-- Warnings -->
        <div
          v-if="warnings.length"
          class="mb-4 rounded-md border border-amber-400 bg-amber-50 p-3 text-sm text-amber-800 dark:bg-amber-900/40 dark:text-amber-200">
          <ul class="list-inside list-disc space-y-1">
            <li
              v-for="(warning, i) in warnings"
              :key="i">
              {{ warning }}
            </li>
          </ul>
        </div>

        <!-- Output tabs -->
        <div class="mb-3 flex items-center justify-between border-b border-gray-200 dark:border-gray-700">
          <nav class="-mb-px flex">
            <button
              v-for="output in outputs"
              :key="output.key"
              type="button"
              @click="activeOutput = output.key"
              class="px-4 py-2 font-mono text-sm font-medium"
              :class="[
                activeOutput === output.key
                  ? 'border-b-2 border-brand-500 text-brand-600 dark:text-brand-400'
                  : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300',
              ]">
              {{ output.label }}
            </button>
          </nav>

          <div class="flex items-center gap-1 pb-1">
            <button
              type="button"
              @click="copyActive"
              class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-800"
              :title="`Copy ${activeOutputMeta.label}`">
              <OIcon
                collection="heroicons"
                :name="copied ? 'check' : 'clipboard-document'"
                size="4" />
              {{ copied ? 'Copied' : 'Copy' }}
            </button>
            <button
              type="button"
              @click="downloadActive"
              class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-800"
              :title="`Download ${activeOutputMeta.filename}`">
              <OIcon
                collection="heroicons"
                name="arrow-down-tray"
                size="4" />
              Download
            </button>
          </div>
        </div>

        <div
          class="overflow-auto rounded-md border border-gray-300 bg-gray-50 dark:border-gray-600 dark:bg-gray-800">
          <CodeMirror
            :model-value="activeContent"
            :key="`cg-${activeOutput}-${isDarkMode}`"
            :lang="lang"
            :extensions="extensions"
            :disabled="true"
            :readonly="true"
            class="max-h-[70vh] min-h-[300px] text-sm" />
        </div>

        <p class="mt-3 text-xs text-gray-500 dark:text-gray-400">
          Secrets (<code>SECRET</code>, database URLs, credentials) are shown only as empty
          placeholders in the <code class="font-mono">.env</code> tab — generate and store those
          yourself, and never paste them into a shared link.
        </p>
      </section>
    </div>
  </div>
</template>
