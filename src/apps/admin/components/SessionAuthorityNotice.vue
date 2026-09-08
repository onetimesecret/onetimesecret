<!-- src/apps/admin/components/SessionAuthorityNotice.vue -->

<script setup lang="ts">
  import type { SessionAuthority } from '@/schemas/api/internal/responses/colonel-sessions';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * "This list is not the session authority" notice for the colonel session
   * views (the sessions console and the per-customer sessions panel).
   *
   * Both views read the Redis session store, which is authoritative only in
   * simple auth mode. In full mode the authoritative session state lives in
   * the Rodauth accounts database, which this console deliberately does not
   * read (rodauth-admin CHARTER §4, seam 2): the console SAYS so and hands the
   * operator over to the standalone Rodauth Admin. The server decides — the
   * `session_authority` block on the listing response carries the mode and,
   * when RODAUTH_ADMIN_URL is configured, the outbound link. Nothing is ever
   * requested from the admin; unset renders a hint instead of a link.
   *
   * Renders nothing when the store IS authoritative, or when a backend
   * predating the signal sends no block at all (deploy skew must not add a
   * scary banner to a simple-mode console).
   */
  const props = defineProps<{
    authority: SessionAuthority | null | undefined;
  }>();

  const { t } = useI18n();

  const visible = computed(() => !!props.authority && !props.authority.authoritative);
  const adminUrl = computed(() => props.authority?.rodauth_admin_url ?? null);
</script>

<template>
  <div
    v-if="visible"
    class="flex items-start gap-3 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 dark:border-amber-900/50 dark:bg-amber-900/20"
    role="status"
    data-testid="session-authority-notice">
    <OIcon
      collection="heroicons"
      name="exclamation-triangle"
      size="5"
      class="mt-0.5 shrink-0 text-amber-600 dark:text-amber-400" />
    <div class="min-w-0 space-y-1 text-sm">
      <p class="font-medium text-amber-900 dark:text-amber-100">
        {{ t('web.admin.sessions.authority.title') }}
      </p>
      <p class="text-amber-800 dark:text-amber-200">
        {{ t('web.admin.sessions.authority.description') }}
      </p>
      <a
        v-if="adminUrl"
        :href="adminUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 font-medium text-amber-900 underline hover:text-amber-700 dark:text-amber-100 dark:hover:text-amber-300"
        data-testid="session-authority-link">
        {{ t('web.admin.sessions.authority.openAdmin') }}
        <OIcon
          collection="heroicons"
          name="arrow-top-right-on-square"
          size="3.5" />
      </a>
      <p
        v-else
        class="text-xs text-amber-700 dark:text-amber-300"
        data-testid="session-authority-unlinked">
        {{ t('web.admin.sessions.authority.notConfigured') }}
      </p>
    </div>
  </div>
</template>
