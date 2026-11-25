<!-- src/shared/components/ui/SettingsCard.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';

  /**
   * The card a settings screen is built from: a header (optional icon tile,
   * title, optional description and actions), a padded body, and an optional
   * footer for the card's own actions.
   *
   * Attributes fall through to the root <section>, so a tabbed page can make
   * the card its tabpanel (id, role, aria-labelledby).
   *
   * `variant` exists because two shells are in use: 'solid' on the domain
   * pages and 'glass' on the organization pages. A card takes the shell of
   * the page it sits on, so it matches its neighbours. Settling on one shell
   * is then a change to this file alone.
   */
  withDefaults(
    defineProps<{
      title: string;
      description?: string;
      /** A heroicons name, shown in a tile beside the title. */
      icon?: string;
      /** The heading level the title takes in the page outline. */
      headingLevel?: 2 | 3;
      variant?: 'solid' | 'glass';
    }>(),
    { description: undefined, icon: undefined, headingLevel: 2, variant: 'solid' }
  );
</script>

<template>
  <section
    :class="[
      'rounded-lg border',
      variant === 'glass'
        ? 'border-gray-200/60 bg-white/60 shadow-sm backdrop-blur-sm dark:border-gray-700/60 dark:bg-gray-800/60'
        : 'border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800',
    ]">
    <div
      class="flex items-center justify-between gap-4 border-b border-gray-200 px-6 py-4 dark:border-gray-700">
      <div class="flex min-w-0 items-center gap-3">
        <div
          v-if="icon"
          data-testid="settings-card-icon"
          class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
          <OIcon
            collection="heroicons"
            :name="icon"
            class="size-5 text-brand-600 dark:text-brand-400"
            aria-hidden="true" />
        </div>
        <div class="min-w-0">
          <!-- mb-0: the base layer gives h2 and h3 a bottom margin, which
               pushes the title off the icon tile's centre line. -->
          <component
            :is="`h${headingLevel}`"
            class="mb-0 text-base font-semibold text-gray-900 dark:text-white">
            {{ title }}
          </component>
          <p
            v-if="description"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ description }}
          </p>
        </div>
      </div>
      <div
        v-if="$slots.actions"
        class="shrink-0">
        <slot name="actions"></slot>
      </div>
    </div>

    <div class="p-6">
      <slot></slot>
    </div>

    <div
      v-if="$slots.footer"
      class="flex items-center justify-end gap-3 border-t border-gray-200 px-6 py-4 dark:border-gray-700">
      <slot name="footer"></slot>
    </div>
  </section>
</template>
