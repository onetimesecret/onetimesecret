<!-- src/apps/admin/components/RevealEmail.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import CopyButton from '@/shared/components/ui/CopyButton.vue';
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * The console-wide "obscure by default, reveal on interaction" email pattern.
   *
   * Every admin surface that displays a customer/owner/billing address wraps it
   * here so a shoulder-surfer / screen-share never leaks a full address by
   * default. The obscuring is purely presentational (computed client-side,
   * mirroring the spirit of the backend's old masking) — the full value is
   * already in the DOM once fetched, so this is a UX guard, not a security
   * boundary. Toggling reveal exposes the address plus a copy affordance.
   *
   * Null/empty → an em dash (matches the rest of the admin read-outs).
   */
  const props = defineProps<{
    /** The address to display, or null/empty for the em-dash placeholder. */
    email: string | null;
  }>();

  const { t } = useI18n();

  const revealed = ref(false);

  const hasEmail = computed(() => typeof props.email === 'string' && props.email.trim().length > 0);

  /**
   * Obscure an address as `f•••@e•••.com`: first char of the local part, first
   * char of the domain label, and the public suffix kept; everything else
   * replaced by a fixed `•••`. Degrades gracefully for addresses without an `@`
   * or without a dot (obscure the middle, keep the ends).
   */
  const obscured = computed(() => {
    const value = (props.email ?? '').trim();
    if (!value) return '—';

    const at = value.indexOf('@');
    if (at <= 0) {
      // No usable local/domain split — keep first + last char only.
      if (value.length <= 2) return `${value[0]}•••`;
      return `${value[0]}•••${value[value.length - 1]}`;
    }

    const local = value.slice(0, at);
    const domain = value.slice(at + 1);
    const localPart = `${local[0]}•••`;

    const dot = domain.lastIndexOf('.');
    if (dot <= 0) {
      return `${localPart}@${domain[0]}•••`;
    }
    const tld = domain.slice(dot + 1);
    return `${localPart}@${domain[0]}•••.${tld}`;
  });

  const displayValue = computed(() => (revealed.value ? props.email : obscured.value));

  function toggle(): void {
    revealed.value = !revealed.value;
  }
</script>

<template>
  <span
    v-if="!hasEmail"
    class="text-gray-400 dark:text-gray-500"
    data-testid="reveal-email-empty"
    >—</span
  >
  <span
    v-else
    class="inline-flex items-center gap-1.5"
    data-testid="reveal-email">
    <span
      class="break-all"
      :class="revealed ? '' : 'font-mono tracking-tight text-gray-500 dark:text-gray-400'"
      data-testid="reveal-email-value">
      {{ displayValue }}
    </span>
    <button
      type="button"
      :aria-label="
        revealed ? t('web.admin.kit.revealEmail.hide') : t('web.admin.kit.revealEmail.reveal')
      "
      :aria-pressed="revealed"
      data-testid="reveal-email-toggle"
      class="shrink-0 rounded text-gray-400 hover:text-gray-700 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-500 dark:hover:text-gray-200"
      @click="toggle">
      <OIcon
        collection="heroicons"
        :name="revealed ? 'eye-slash' : 'eye'"
        size="4" />
    </button>
    <CopyButton
      v-if="revealed && email"
      :text="email"
      :tooltip="t('web.admin.kit.revealEmail.copy')"
      testid="reveal-email-copy" />
  </span>
</template>
