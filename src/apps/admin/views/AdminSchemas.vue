<!-- src/apps/admin/views/AdminSchemas.vue -->

<script setup lang="ts">
  import { allSchemas, checkPayload, closest, counted } from '@/schemas/check';
  import type { Candidate, CheckResult } from '@/schemas/check';
  import { withoutSchemaDiagnostics } from '@/schemas/validationContext';
  import { computed, ref, shallowRef, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const schemas = allSchemas();
  const names = [...schemas.keys()].sort();
  const search = ref('');
  const selected = ref('v3.secret');
  const payload = ref('');
  const report = shallowRef<CheckResult | null>(null);
  const candidates = shallowRef<Candidate[]>([]);
  const errorKey = ref('');

  const filteredNames = computed(() => {
    const query = search.value.trim().toLowerCase();
    return names.filter((name) => name.toLowerCase().includes(query));
  });

  function resetReport(): void {
    report.value = null;
    candidates.value = [];
    errorKey.value = '';
  }

  // A report only describes the exact schema and payload last checked.
  watch([selected, payload], resetReport, { flush: 'sync' });

  function validate(): void {
    resetReport();
    let input: unknown;
    try {
      input = JSON.parse(payload.value);
    } catch {
      // JSON.parse errors can quote payload content; never render the exception.
      errorKey.value = 'web.admin.schemas.invalidJson';
      return;
    }

    const schema = schemas.get(selected.value);
    if (!schema) return;
    try {
      // Schema transforms normally report application drift. Pasted documents
      // and candidate ranking must not enter that telemetry path.
      withoutSchemaDiagnostics(() => {
        const result = checkPayload(schema, input);
        if (!result.success) candidates.value = closest(input, schemas);
        report.value = result;
      });
    } catch {
      // Transforms and synchronous checks of async refinements can throw.
      errorKey.value = 'web.admin.schemas.checkError';
    }
  }

  function clear(): void {
    payload.value = '';
    resetReport();
  }
</script>

<template>
  <div class="space-y-6">
    <header>
      <h2 class="font-brand text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.admin.schemas.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.schemas.description') }}
      </p>
      <p class="mt-3 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.schemas.privacy') }}
      </p>
    </header>

    <div class="grid items-start gap-6 xl:grid-cols-[20rem_minmax(0,1fr)]">
      <section
        class="min-w-0 border border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900"
        aria-labelledby="schema-list-heading">
        <div class="space-y-3 border-b border-gray-200 p-4 dark:border-gray-800">
          <h3
            id="schema-list-heading"
            class="font-brand font-semibold">
            {{ t('web.admin.schemas.available', { count: names.length }) }}
          </h3>
          <label
            for="schema-search"
            class="block text-sm font-medium">
            {{ t('web.admin.schemas.search') }}
          </label>
          <input
            id="schema-search"
            v-model="search"
            type="search"
            autocomplete="off"
            class="w-full rounded-md border-gray-300 bg-white text-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-700 dark:bg-gray-950"
            :placeholder="t('web.admin.schemas.searchPlaceholder')" />
        </div>
        <ul
          class="max-h-96 overflow-y-auto xl:max-h-144"
          data-testid="schema-list">
          <li
            v-for="name in filteredNames"
            :key="name">
            <button
              type="button"
              class="w-full border-l-2 px-4 py-2 text-left font-mono text-xs break-all focus:ring-2 focus:ring-brand-500 focus:outline-none focus:ring-inset"
              :class="
                selected === name
                  ? 'border-brand-600 bg-brand-50 text-brand-700 dark:border-brand-400 dark:bg-brand-500/10 dark:text-brand-200'
                  : 'border-transparent text-gray-600 hover:bg-gray-50 dark:text-gray-400 dark:hover:bg-gray-800'
              "
              :aria-pressed="selected === name"
              :data-schema="name"
              @click="selected = name">
              {{ name }}
            </button>
          </li>
        </ul>
        <p
          v-if="!filteredNames.length"
          class="p-4 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.schemas.noMatches') }}
        </p>
      </section>

      <div class="min-w-0 space-y-6">
        <form
          class="space-y-4 border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-900"
          @submit.prevent="validate">
          <h3 class="font-brand font-semibold">
            {{ t('web.admin.schemas.checkTitle') }}
          </h3>
          <p
            class="font-mono text-sm break-all"
            data-testid="selected-schema">
            {{ selected }}
          </p>
          <label
            for="schema-payload"
            class="block text-sm font-medium">
            {{ t('web.admin.schemas.payload') }}
          </label>
          <textarea
            id="schema-payload"
            v-model="payload"
            rows="14"
            autocomplete="off"
            autocapitalize="off"
            :spellcheck="false"
            data-sentry-block
            class="w-full rounded-md border-gray-300 bg-white font-mono text-xs focus:border-brand-500 focus:ring-brand-500 dark:border-gray-700 dark:bg-gray-950"
            :placeholder="t('web.admin.schemas.payloadPlaceholder')"></textarea>
          <div class="flex flex-wrap gap-3">
            <button
              type="submit"
              :disabled="!payload.trim()"
              class="rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
              data-testid="validate-payload">
              {{ t('web.admin.schemas.validate') }}
            </button>
            <button
              type="button"
              class="rounded-md border border-gray-300 px-4 py-2 text-sm font-medium hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-700 dark:hover:bg-gray-800"
              data-testid="clear-payload"
              @click="clear">
              {{ t('web.admin.schemas.clear') }}
            </button>
          </div>
        </form>

        <div
          aria-live="polite"
          aria-atomic="true"
          data-sentry-block>
          <p
            v-if="errorKey"
            role="alert"
            class="border border-red-200 bg-red-50 p-4 text-sm text-red-800 dark:border-red-900 dark:bg-red-950/30 dark:text-red-200"
            data-testid="schema-input-error">
            {{ t(errorKey) }}
          </p>
          <section
            v-if="report"
            class="space-y-4 border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-900"
            aria-labelledby="schema-result-heading"
            data-testid="schema-report">
            <h3
              id="schema-result-heading"
              class="font-brand font-semibold"
              :class="
                report.success
                  ? 'text-green-700 dark:text-green-300'
                  : 'text-red-700 dark:text-red-300'
              ">
              {{
                report.success
                  ? t('web.admin.schemas.valid', { schema: selected })
                  : t('web.admin.schemas.invalid', { schema: selected, count: report.issueCount })
              }}
            </h3>
            <p
              v-if="report.undeclared.length"
              class="text-sm text-amber-700 dark:text-amber-300">
              {{ t('web.admin.schemas.undeclaredHint') }}
            </p>
            <div
              v-for="[path, group] in report.groups"
              :key="path"
              class="space-y-2 border-t border-gray-200 pt-3 font-mono text-xs break-all dark:border-gray-800">
              <h4 class="font-semibold">
                {{ path }}
              </h4>
              <p v-if="group.missing.size">
                {{ t('web.admin.schemas.missing') }}: {{ counted(group.missing).join(', ') }}
              </p>
              <p v-if="group.undeclared.size">
                {{ t('web.admin.schemas.undeclared') }}: {{ [...group.undeclared].join(', ') }}
              </p>
              <ul
                v-if="group.problems.size"
                class="space-y-1">
                <li
                  v-for="problem in counted(group.problems)"
                  :key="problem">
                  {{ problem }}
                </li>
              </ul>
            </div>
          </section>
        </div>

        <section
          v-if="candidates.length"
          class="space-y-3 border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-900"
          aria-labelledby="schema-candidates-heading"
          data-testid="schema-candidates">
          <h3
            id="schema-candidates-heading"
            class="font-brand font-semibold">
            {{ t('web.admin.schemas.closest') }}
          </h3>
          <p class="text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.schemas.closestHint') }}
          </p>
          <ul class="space-y-3">
            <li
              v-for="candidate in candidates"
              :key="candidate.name">
              <button
                type="button"
                class="rounded font-mono text-xs break-all text-brand-700 underline focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-brand-300"
                @click="selected = candidate.name">
                {{ candidate.name }}
              </button>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.schemas.candidateStats', { ...candidate }) }}
              </p>
            </li>
          </ul>
        </section>
      </div>
    </div>
  </div>
</template>
