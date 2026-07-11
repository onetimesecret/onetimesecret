<!-- src/apps/admin/components/kit/AdminRecordPanel.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useI18n } from 'vue-i18n';

  /**
   * A "pinned working record" section for admin screens — the surface an
   * operator pulls a single record into (from a picker) to inspect or act on it,
   * distinct from the paginated list below. On the Domains screen it sits between
   * the page rule and the domain grid; the pattern is deliberately generic so
   * other console screens (customers, organizations) can adopt it.
   *
   * Chrome only: a left accent bar marking it as the active focus, an identity
   * header (title + key-material subtitle), a trailing `actions` slot for
   * record-scoped buttons, a `clear` (dismiss) control, and the record body via
   * the default slot. It owns no data — the caller supplies identity + content.
   */
  withDefaults(
    defineProps<{
      /** Record identity heading (already translated or a display value). */
      title?: string;
      /** Secondary identity line — rendered as key material (mono/tabular). */
      subtitle?: string;
      /** Small uppercase eyebrow above the title (e.g. the record kind). */
      eyebrow?: string;
      /** Show the dismiss (clear) control. */
      dismissable?: boolean;
      /** Test id applied to the section. */
      testid?: string;
    }>(),
    {
      title: undefined,
      subtitle: undefined,
      eyebrow: undefined,
      dismissable: true,
      testid: undefined,
    }
  );

  const emit = defineEmits<{
    clear: [];
  }>();

  const { t } = useI18n();
</script>

<template>
  <section
    :data-testid="testid"
    class="mb-8 overflow-hidden rounded-lg border border-l-4 border-gray-200 border-l-brand-600 bg-white shadow-sm dark:border-gray-700 dark:border-l-brand-500 dark:bg-gray-900">
    <!-- Identity header -->
    <div
      class="flex items-start justify-between gap-4 border-b border-gray-200 bg-gray-50 px-5 py-4 dark:border-gray-700 dark:bg-gray-800/50">
      <div class="min-w-0">
        <slot name="header">
          <p
            v-if="eyebrow"
            class="mb-1 text-xs font-semibold tracking-wide text-brand-600 uppercase dark:text-brand-400">
            {{ eyebrow }}
          </p>
          <h3
            v-if="title"
            class="truncate font-brand text-xl font-bold text-gray-900 dark:text-white">
            {{ title }}
          </h3>
          <p
            v-if="subtitle"
            class="mt-0.5 truncate font-mono text-xs text-gray-500 tabular-nums dark:text-gray-400">
            {{ subtitle }}
          </p>
        </slot>
      </div>

      <div class="flex shrink-0 items-center gap-2">
        <slot name="actions"></slot>
        <button
          v-if="dismissable"
          type="button"
          data-testid="record-panel-clear"
          class="-m-1.5 rounded-md p-1.5 text-gray-400 hover:text-gray-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:hover:text-gray-200"
          :aria-label="t('web.LABELS.close')"
          @click="emit('clear')">
          <OIcon
            collection="heroicons"
            name="x-mark"
            size="5" />
        </button>
      </div>
    </div>

    <!-- Record body -->
    <div class="p-5">
      <slot></slot>
    </div>
  </section>
</template>
