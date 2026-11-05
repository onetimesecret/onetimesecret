<!-- src/apps/admin/components/ElevationBanner.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import PasswordConfirmModal from '@/shared/components/modals/PasswordConfirmModal.vue';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { useColonelElevation } from '../composables/useColonelElevation';
  import { recoverAdminSession } from '../utils/adminSessionExpiry';
  import { formatElevationCountdown } from '../utils/elevationCountdown';

  /**
   * A live step-up (sudo) window, shown while one is open (#4327), and the
   * expired-admin-session notice (#4331).
   *
   * Mounted once in AdminLayout. Renders NOTHING when elevation is disabled by
   * config or when no window is live — the console's ordinary state is
   * unelevated, and a permanent "you are not elevated" bar would train operators
   * to ignore the bar that matters.
   *
   * The countdown is driven entirely by {@link useColonelElevation}'s local
   * timer: this component issues NO HTTP of its own, ever, and the composable's
   * doc block explains why that is a shipped security property rather than a
   * style choice (a poll would re-stamp last_activity_at and make #4331's idle
   * timeout unreachable while an admin tab is open).
   *
   * A window minted with `recent_auth` is labelled DIFFERENTLY: that path
   * elevates without a credential, so it must be visible while it is live rather
   * than indistinguishable from a password step-up.
   *
   * The EXPIRED state (#4331) takes priority over both elevation states, and is
   * the reason this component renders at all on a dead session: the admin API
   * surface has its own idle/absolute bounds, but the /colonel shell is
   * deliberately NOT gated, so the SPA loads, its first API call 401s, and this
   * is where the operator learns why nothing works. An elevation window is
   * meaningless once the surface itself refuses the session, so it is not shown
   * alongside.
   *
   * Recovery from the expired state is a password re-authentication first
   * (POST /api/colonel/reauthenticate, exempt from the admin bound): the
   * operator stays on the page and it reloads in place. "Sign in" stays as the
   * second way out for an account with no password (SSO-only), which the
   * re-authentication cannot serve. The banner usually cannot tell which
   * account it has, because the status read that would say so is itself
   * refused while expired; it hides the password action only when an earlier
   * status read already reported no password.
   */
  const { t } = useI18n();

  const elevation = useColonelElevation();

  // The one status fetch the console makes on entry. Everything after this is
  // triggered by an operator action or a 403. It is also, on a stale tab, the
  // request that discovers the expired admin window.
  onMounted(() => {
    void elevation.refresh();
  });

  const expired = computed(() => elevation.adminSessionExpired.value);

  const visible = computed(
    () => !expired.value && elevation.enabled.value && elevation.elevated.value
  );

  const viaRecentAuth = computed(() => elevation.activeFactor.value === 'recent_auth');

  /** mm:ss, computed locally from the expiry — no request per tick. */
  const remaining = computed(() => formatElevationCountdown(elevation.secondsRemaining.value));

  // ---- Re-authenticate the expired admin session by password ---------------

  /**
   * `passwordAvailable` defaults to true and turns false only when a status
   * read said so, so an unknown account still gets the password action.
   */
  const canReauthenticate = computed(() => elevation.passwordAvailable.value);

  const reauthOpen = ref(false);

  function openReauth(): void {
    elevation.reauthError.value = null;
    reauthOpen.value = true;
  }

  function closeReauth(): void {
    reauthOpen.value = false;
    elevation.reauthError.value = null;
  }

  function onReauthOpenChange(open: boolean): void {
    if (!open) closeReauth();
  }

  async function onReauth(password: string): Promise<void> {
    // Success reloads the page; a failure keeps the modal open with the
    // server's message.
    if (await elevation.reauthenticate(password)) reauthOpen.value = false;
  }
</script>

<template>
  <div
    v-if="expired"
    class="flex items-center justify-between gap-3 border-b border-red-300 bg-red-50 px-5 py-2 text-sm text-red-900 sm:px-8 dark:border-red-700 dark:bg-red-950/50 dark:text-red-200"
    role="alert"
    data-testid="admin-session-expired-banner">
    <span class="flex min-w-0 items-center gap-2">
      <OIcon
        collection="heroicons"
        name="exclamation-triangle"
        size="4"
        aria-hidden="true" />
      <span class="truncate">{{ t('web.admin.session.expired') }}</span>
    </span>

    <span class="flex shrink-0 items-center gap-2">
      <!-- Primary: re-enter the password in place; the page reloads on success. -->
      <button
        v-if="canReauthenticate"
        type="button"
        class="rounded bg-red-700 px-2.5 py-1 font-semibold text-white hover:bg-red-800 focus:ring-2 focus:ring-red-500 focus:ring-offset-1 focus:outline-none dark:bg-red-600 dark:hover:bg-red-500"
        data-testid="admin-session-reauth"
        @click="openReauth">
        {{ t('web.admin.session.reauth.button') }}
      </button>

      <!--
        Secondary, and the only way out for an account with no password.
        Recovery CLEARS the session before sign-in (#4331): a bare link to
        /signin is a no-op in simple mode while the cookie still reads
        authenticated. See recoverAdminSession.
      -->
      <button
        type="button"
        class="rounded px-2 py-1 font-semibold underline underline-offset-2 hover:bg-black/5 dark:hover:bg-white/10"
        data-testid="admin-session-signin"
        @click="recoverAdminSession">
        {{ t('web.admin.session.signIn') }}
      </button>
    </span>

    <PasswordConfirmModal
      :open="reauthOpen"
      :title="t('web.admin.session.reauth.title')"
      :description="t('web.admin.session.reauth.description')"
      :confirm-text="t('web.admin.session.reauth.confirm')"
      :loading="elevation.reauthLoading.value"
      :error="elevation.reauthError.value"
      data-testid="admin-session-reauth-modal"
      @confirm="onReauth"
      @cancel="closeReauth"
      @update:open="onReauthOpenChange" />
  </div>

  <div
    v-else-if="visible"
    class="flex items-center justify-between gap-3 border-b px-5 py-2 text-sm sm:px-8"
    :class="
      viaRecentAuth
        ? 'border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-700 dark:bg-amber-950/50 dark:text-amber-200'
        : 'border-brand-200 bg-brand-50 text-brand-900 dark:border-brand-800 dark:bg-brand-950/50 dark:text-brand-200'
    "
    data-testid="elevation-banner">
    <span class="flex min-w-0 items-center gap-2">
      <OIcon
        collection="heroicons"
        :name="viaRecentAuth ? 'exclamation-triangle' : 'lock-open'"
        size="4"
        aria-hidden="true" />
      <span class="truncate">
        {{
          viaRecentAuth
            ? t('web.admin.elevation.banner.activeRecentAuth', { remaining })
            : t('web.admin.elevation.banner.active', { remaining })
        }}
      </span>
    </span>

    <button
      type="button"
      class="shrink-0 rounded px-2 py-1 font-semibold underline underline-offset-2 hover:bg-black/5 disabled:opacity-50 dark:hover:bg-white/10"
      :disabled="elevation.loading.value"
      data-testid="elevation-drop"
      @click="elevation.drop()">
      {{ t('web.admin.elevation.banner.drop') }}
    </button>
  </div>
</template>
