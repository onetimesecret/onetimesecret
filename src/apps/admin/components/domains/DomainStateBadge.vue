<!-- src/apps/admin/components/domains/DomainStateBadge.vue -->

<script setup lang="ts">
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Verification-state pill for a custom domain.
   *
   * Presentational only. Extracted so the domains LIST, its detail drawer and
   * the full detail page render the operator-facing state with one set of
   * colours and one label map — the previous copies drifted apart.
   *
   * The state string comes straight from the backend
   * (`CustomDomain#verification_state`): verified / resolving / pending, with
   * anything unknown rendered verbatim rather than swallowed.
   */
  const props = withDefaults(
    defineProps<{
      /** Backend verification state (verified | resolving | pending | …). */
      state: string;
      /** Optional test id for the pill. */
      testid?: string;
    }>(),
    { testid: undefined }
  );

  const { t } = useI18n();

  const badgeClass = computed(() => {
    switch (props.state) {
      case 'verified':
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
      case 'pending':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
      case 'resolving':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200';
    }
  });

  /**
   * Reuses the existing colonel status labels. Unknown states fall back to the
   * raw value (vue-i18n returns the key when missing, so we guard explicitly).
   */
  const label = computed(() => {
    const key = `web.colonel.customDomains.status.${props.state}`;
    const translated = t(key);
    return translated === key ? props.state : translated;
  });
</script>

<template>
  <span
    :class="['inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium', badgeClass]"
    :data-testid="testid">
    {{ label }}
  </span>
</template>
