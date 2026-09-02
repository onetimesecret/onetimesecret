<!-- src/apps/admin/components/ElevationPrompt.vue -->

<script setup lang="ts">
  import PasswordConfirmModal from '@/shared/components/modals/PasswordConfirmModal.vue';
  import { computed, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { useColonelElevation } from '../composables/useColonelElevation';

  /**
   * The step-up (sudo) prompt (#4327).
   *
   * Mounted ONCE, in AdminLayout, and driven by the module-level state in
   * {@link useColonelElevation}: a destructive mutation anywhere in the console
   * calls `requestElevation()`, this opens, and the promise resolves when the
   * operator finishes or dismisses.
   *
   * ## It always requires an explicit operator gesture
   *
   * There is no grace-first auto-elevation. The rejected first draft called
   * `elevate('recent_auth')` silently on open and retried the failed verb when
   * it succeeded, which made step-up a no-op for the first N seconds after every
   * colonel sign-in. Three forks, all operator-initiated:
   *
   *   1. the account has a password (the normal case) — re-enter it;
   *   2. the account has none and an operator configured a grace — ONE deliberate
   *      "confirm it's you" click, never fired on mount;
   *   3. the account has none and no grace is configured — nothing the operator
   *      can do from the browser, so render the remediation and no input at all,
   *      rather than looping on an unsatisfiable prompt.
   *
   * Imports from `@/shared/*` only. `src/apps/session/*` is banned here: the
   * admin bundle is code-split-free, so one session import would drag the whole
   * customer auth graph into it (admin-isolation.spec.ts).
   */
  const { t } = useI18n();

  const elevation = useColonelElevation();

  const usePasswordFork = computed(
    () => elevation.passwordAvailable.value && elevation.factors.value.includes('password')
  );
  const useGraceFork = computed(
    () => !elevation.passwordAvailable.value && elevation.factors.value.includes('recent_auth')
  );

  const windowMinutes = computed(() => Math.max(1, Math.round(elevation.window.value / 60)));

  // Refresh the per-account capability the moment the prompt opens, so the fork
  // below is decided on current server state rather than whatever was last seen.
  watch(
    () => elevation.promptOpen.value,
    (open) => {
      if (open) void elevation.refresh();
      else elevation.error.value = null;
    }
  );

  async function onPassword(password: string): Promise<void> {
    if (await elevation.elevate('password', password)) elevation.resolvePrompt(true);
  }

  async function onGrace(): Promise<void> {
    if (await elevation.elevate('recent_auth')) elevation.resolvePrompt(true);
  }

  function onCancel(): void {
    elevation.resolvePrompt(false);
  }
</script>

<template>
  <!-- Fork 1: the account has a password. The shared modal already owns the
       input, visibility toggle, focus management and the confirm/cancel emits. -->
  <PasswordConfirmModal
    v-if="usePasswordFork"
    :open="elevation.promptOpen.value"
    :title="t('web.admin.elevation.prompt.title')"
    :description="t('web.admin.elevation.prompt.description', { minutes: windowMinutes })"
    :confirm-text="t('web.admin.elevation.prompt.confirm')"
    :loading="elevation.loading.value"
    :error="elevation.error.value"
    variant="danger"
    data-testid="elevation-prompt-password"
    @confirm="onPassword"
    @cancel="onCancel"
    @update:open="(value: boolean) => { if (!value) onCancel(); }" />

  <!-- Forks 2 and 3 share a plain panel: neither takes a credential, and the
       shared password modal cannot render without its input. -->
  <div
    v-else-if="elevation.promptOpen.value"
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-500/75 p-4 dark:bg-gray-900/80"
    role="dialog"
    aria-modal="true"
    :aria-label="t('web.admin.elevation.prompt.title')">
    <div
      class="w-full max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900"
      data-testid="elevation-prompt-alt">
      <h2 class="font-brand text-lg font-bold text-gray-900 dark:text-gray-100">
        {{ t('web.admin.elevation.prompt.title') }}
      </h2>

      <template v-if="useGraceFork">
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-300">
          {{ t('web.admin.elevation.prompt.confirmItsYouDescription', { minutes: windowMinutes }) }}
        </p>
        <p
          v-if="elevation.error.value"
          class="mt-3 text-sm text-red-600 dark:text-red-400"
          data-testid="elevation-prompt-error">
          {{ elevation.error.value }}
        </p>
        <div class="mt-5 flex justify-end gap-3">
          <button
            type="button"
            class="rounded-md px-4 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-gray-800"
            @click="onCancel">
            {{ t('web.COMMON.word_cancel') }}
          </button>
          <!-- ONE deliberate click. Never fired on mount, never on a watcher. -->
          <button
            type="button"
            class="rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50"
            :disabled="elevation.loading.value"
            data-testid="elevation-confirm-its-you"
            @click="onGrace">
            {{ t('web.admin.elevation.prompt.confirmItsYou') }}
          </button>
        </div>
      </template>

      <!-- Fork 3: password-less account, no grace configured. There is no input
           to render — only the remediation an administrator must apply. -->
      <template v-else>
        <p
          class="mt-2 text-sm text-gray-600 dark:text-gray-300"
          data-testid="elevation-prompt-unsatisfiable">
          {{ t('web.admin.elevation.errors.noPassword') }}
        </p>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.elevation.errors.noGrace') }}
        </p>
        <div class="mt-5 flex justify-end">
          <button
            type="button"
            class="rounded-md bg-gray-200 px-4 py-2 text-sm font-semibold text-gray-800 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-100 dark:hover:bg-gray-600"
            @click="onCancel">
            {{ t('web.LABELS.close') }}
          </button>
        </div>
      </template>
    </div>
  </div>
</template>
