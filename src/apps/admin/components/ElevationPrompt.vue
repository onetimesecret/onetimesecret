<!-- src/apps/admin/components/ElevationPrompt.vue -->

<script setup lang="ts">
  import PasswordConfirmModal from '@/shared/components/modals/PasswordConfirmModal.vue';
  import { computed, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { useColonelElevation } from '../composables/useColonelElevation';
  import AdminModal from './kit/AdminModal.vue';

  /**
   * The step-up (sudo) prompt (#4327).
   *
   * ONE instance is mounted at a time, driven by the module-level state in
   * {@link useColonelElevation}: a destructive mutation anywhere in the console
   * calls `requestElevation()`, this opens, and the promise resolves when the
   * operator finishes or dismisses. AdminLayout mounts it while no admin kit
   * dialog is open; otherwise the top-most open kit dialog does, nested inside
   * its headlessui Dialog (useElevationPromptHost explains why).
   *
   * Every fork renders through a headlessui Dialog, so it is portaled out of
   * #app (which an open dialog makes inert) and nests under its host.
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
   * Imports from `@/shared/*` only. `src/apps/session/*` is banned here: one
   * session import would pull the whole customer auth graph into the chunks
   * the admin entry loads, which the bundle-isolation guard forbids
   * (admin-isolation.spec.ts, CONTRACT 6).
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

  // Each completion settles the prompt cycle it was started in. If this cycle
  // is cancelled while the request is in flight and a newer one opens, the late
  // success must not resolve the newer caller's request.
  async function onPassword(password: string): Promise<void> {
    const generation = elevation.promptGeneration.value;
    if (await elevation.elevate('password', password)) elevation.resolvePrompt(true, generation);
  }

  async function onGrace(): Promise<void> {
    const generation = elevation.promptGeneration.value;
    if (await elevation.elevate('recent_auth')) elevation.resolvePrompt(true, generation);
  }

  function onCancel(): void {
    elevation.resolvePrompt(false, elevation.promptGeneration.value);
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

  <!-- Forks 2 and 3 share the kit's modal shell: neither takes a credential,
       and the shared password modal cannot render without its input. -->
  <AdminModal
    v-else
    :open="elevation.promptOpen.value"
    :title="t('web.admin.elevation.prompt.title')"
    width-class="max-w-md"
    testid="elevation-prompt-alt"
    @close="onCancel">
    <template v-if="useGraceFork">
      <p class="text-sm text-gray-600 dark:text-gray-300">
        {{ t('web.admin.elevation.prompt.confirmItsYouDescription', { minutes: windowMinutes }) }}
      </p>
      <p
        v-if="elevation.error.value"
        class="mt-3 text-sm text-red-600 dark:text-red-400"
        data-testid="elevation-prompt-error">
        {{ elevation.error.value }}
      </p>
    </template>

    <!-- Fork 3: password-less account, no grace configured. There is no input
         to render — only the remediation an administrator must apply. -->
    <template v-else>
      <p
        class="text-sm text-gray-600 dark:text-gray-300"
        data-testid="elevation-prompt-unsatisfiable">
        {{ t('web.admin.elevation.errors.noPassword') }}
      </p>
      <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.elevation.errors.noGrace') }}
      </p>
    </template>

    <template #footer>
      <div
        v-if="useGraceFork"
        class="flex justify-end gap-3">
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
      <div
        v-else
        class="flex justify-end">
        <button
          type="button"
          class="rounded-md bg-gray-200 px-4 py-2 text-sm font-semibold text-gray-800 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-100 dark:hover:bg-gray-600"
          @click="onCancel">
          {{ t('web.LABELS.close') }}
        </button>
      </div>
    </template>
  </AdminModal>
</template>
