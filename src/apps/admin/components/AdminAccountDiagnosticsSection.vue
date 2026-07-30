<!-- src/apps/admin/components/AdminAccountDiagnosticsSection.vue -->

<script setup lang="ts">
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import {
    colonelAccountDiagnosticsResponseSchema,
    type AccountDiagnosisFinding,
    type ColonelAccountDiagnosticsResponse,
  } from '@/schemas/api/internal/responses/colonel-account-diagnostics';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed, onMounted, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Account auth diagnostics panel — the READ-ONLY sidecar mounted inside
   * {@link AdminCustomerDetail} that answers "why can't this user log in or
   * sign up" without SSH access. Thin view over
   * `GET /api/colonel/users/:user_id/diagnostics`
   * (Auth::Operations::Customers::Diagnose — same read-out as
   * `bin/ots customers diagnose`): a severity-ordered findings list, a compact
   * auth-state fact grid, and the Rodauth authentication-log tail.
   *
   * Sections degrade independently server-side (`available: false`), e.g.
   * simple auth mode has no SQL authdb — the panel renders whatever arrived.
   */
  const props = defineProps<{
    /** The customer's public id (extid, 'ur…'), forwarded from the detail view. */
    userId: string;
  }>();

  const { t } = useI18n();

  const diagnosticsUrl = (): string =>
    `/api/colonel/users/${encodeURIComponent(props.userId)}/diagnostics`;

  const {
    data,
    loading,
    error,
    validationError,
    load: fetchDiagnostics,
  } = useResourceFetch<ColonelAccountDiagnosticsResponse>({
    url: diagnosticsUrl,
    schema: colonelAccountDiagnosticsResponseSchema,
    context: 'ColonelAccountDiagnosticsResponse',
  });

  const loadFailed = computed(() => error.value !== null || validationError.value !== null);

  const findings = computed<AccountDiagnosisFinding[]>(() => data.value?.details?.findings ?? []);
  const sections = computed(() => data.value?.details?.sections ?? null);

  const authAccount = computed(() => sections.value?.auth_account ?? null);

  /**
   * Deliberately `=== false`, NOT the fail-closed test `sectionOk` applies.
   * This flag does not degrade a cell — it hides the entire panel body (fact
   * grid and authentication log) and replaces it with copy that asserts a
   * specific cause: either "simple auth mode" or "the auth database did not
   * answer". Inferring either of those from a field that is merely *absent*
   * would blank the break-glass view and name an outage on no evidence. So the
   * body stays visible when the flag is missing, and the fail-closed guard
   * below stops any individual cell from vouching for a value.
   */
  const authUnavailable = computed(() => authAccount.value?.available === false);

  /**
   * Sections degrade INDEPENDENTLY: `auth_account` can be available while a
   * sidecar read (lockout/sessions/verification/audit_log) failed, and
   * `rate_limits` is not authdb-backed at all (it degrades whenever there is no
   * email to key on — every orphan-by-extid lookup). Every cell must therefore
   * test its OWN section before printing a value, or a failed read renders as a
   * reassuring negative assertion ("0 failures", "Clear", "None pending").
   *
   * Fail-closed: only an explicit `available === true` is usable. The wire
   * schema keeps `available` optional on purpose — requiring it would make a
   * version-skewed payload fail validation, and `useResourceFetch` answers a
   * parse failure by discarding the response, blanking the whole panel during
   * exactly the incident it exists to triage. That leniency is paid for here:
   * a section whose flag never arrived is indistinguishable from one whose read
   * failed, so it renders "Unknown" rather than its benign-looking zero.
   */
  function sectionOk(section?: { available?: boolean } | null): boolean {
    return section?.available === true;
  }

  /**
   * Why the SQL sections are missing decides what to tell the operator, and the
   * two answers point opposite ways: `simple_mode` means there is no authdb by
   * design and nothing is wrong, while anything else means the read FAILED and
   * the outage is itself the likely reason nobody can log in. Saying "simple
   * auth mode" during an outage sends support looking in the wrong place.
   */
  const authUnavailableMessage = computed<string>(() => {
    if (!authUnavailable.value) return '';
    if (authAccount.value?.reason_code === 'simple_mode') {
      return t('web.admin.customers.detail.diagnostics.authUnavailable');
    }
    return t('web.admin.customers.detail.diagnostics.authFailed', {
      reason: authAccount.value?.reason ?? t('web.admin.customers.detail.diagnostics.unknown'),
    });
  });

  function load(): void {
    fetchDiagnostics().catch(() => {
      // Failure surfaces via error → the error state below. Swallow so it
      // doesn't become an unhandled rejection.
    });
  }

  // Refetch if the detail component is reused across a different customer id.
  watch(() => props.userId, load);
  onMounted(load);

  // ---- Presentation helpers -------------------------------------------------

  /** Epoch fields arrive as bare Unix-second numbers. */
  function epochLabel(epoch: number | null | undefined): string {
    if (!epoch) return t('web.admin.customers.detail.diagnostics.unknown');
    return formatDisplayDateTime(new Date(epoch * 1000));
  }

  const CALLOUT_CLASSES: Record<AccountDiagnosisFinding['severity'], string> = {
    critical:
      'border-red-300 bg-red-50 text-red-800 dark:border-red-800 dark:bg-red-900/30 dark:text-red-200',
    warning:
      'border-amber-300 bg-amber-50 text-amber-800 dark:border-amber-700 dark:bg-amber-900/30 dark:text-amber-200',
    info: 'border-blue-300 bg-blue-50 text-blue-800 dark:border-blue-800 dark:bg-blue-900/30 dark:text-blue-200',
  };

  const CALLOUT_ICONS: Record<AccountDiagnosisFinding['severity'], string> = {
    critical: 'exclamation-triangle',
    warning: 'exclamation-circle',
    info: 'information-circle',
  };

  /** MFA summary, e.g. "TOTP + 2 WebAuthn" — or the localized "none". */
  const mfaLabel = computed(() => {
    const mfa = sections.value?.mfa;
    if (!sectionOk(mfa)) return t('web.admin.customers.detail.diagnostics.unknown');
    const parts: string[] = [];
    if (mfa?.otp_enabled) parts.push('TOTP');
    if (mfa?.webauthn_credentials) parts.push(`${mfa.webauthn_credentials} WebAuthn`);
    return parts.length
      ? parts.join(' + ')
      : t('web.admin.customers.detail.diagnostics.facts.mfaNone');
  });

  /** The localized "Unknown" every degraded cell falls back to. */
  const unknownLabel = (): string => t('web.admin.customers.detail.diagnostics.unknown');

  /**
   * "No auth account" is the loudest negative assertion on the panel — it is
   * the answer to "why can't they log in" — so it needs the same guard as the
   * password cell beside it. Absent `found` on an unvouched section is not
   * evidence of a missing row, only of a section that did not say.
   */
  const authStatusLabel = computed<string>(() => {
    if (!sectionOk(authAccount.value)) return unknownLabel();
    if (!authAccount.value?.found) {
      return t('web.admin.customers.detail.diagnostics.facts.noAccount');
    }
    return authAccount.value.status ?? unknownLabel();
  });

  /**
   * "No auth account" and "password not set" are different answers, and the
   * `no_account` path sends `auth_account: { available: true, found: false }` —
   * available, so the grid renders, but there is no row to have a password.
   */
  const passwordLabel = computed<string>(() => {
    if (!sectionOk(authAccount.value)) return unknownLabel();
    if (!authAccount.value?.found) {
      return t('web.admin.customers.detail.diagnostics.facts.noAccount');
    }
    return authAccount.value.has_password
      ? t('web.admin.customers.detail.diagnostics.facts.passwordSet')
      : t('web.admin.customers.detail.diagnostics.facts.passwordNone');
  });

  const loginFailuresLabel = computed<string>(() => {
    const lockout = sections.value?.lockout;
    if (!sectionOk(lockout)) return unknownLabel();
    return String(lockout?.login_failures ?? 0);
  });

  /** Only assert "locked out" from a section that actually answered. */
  const lockedOut = computed(
    () => sectionOk(sections.value?.lockout) && sections.value?.lockout?.locked === true
  );

  /** Drives the red styling only — "unknown" is not an alarm. */
  const rateLimiterEngaged = computed(() => {
    const limits = sections.value?.rate_limits;
    if (!sectionOk(limits)) return false;
    return (limits?.entries ?? []).some(
      (entry) => entry.exists && entry.key.startsWith('login:locked:')
    );
  });

  const rateLimiterLabel = computed<string>(() => {
    if (!sectionOk(sections.value?.rate_limits)) return unknownLabel();
    return rateLimiterEngaged.value
      ? t('web.admin.customers.detail.diagnostics.facts.rateLimiterEngaged')
      : t('web.admin.customers.detail.diagnostics.facts.rateLimiterClear');
  });

  const verificationLabel = computed<string>(() => {
    const verification = sections.value?.verification;
    if (!sectionOk(verification)) return unknownLabel();
    return verification?.pending
      ? t('web.admin.customers.detail.diagnostics.facts.verificationPending', {
          date: epochLabel(verification?.email_last_sent),
        })
      : t('web.admin.customers.detail.diagnostics.facts.verificationNone');
  });

  const sessionsLabel = computed<string>(() => {
    const sessionsSection = sections.value?.sessions;
    if (!sectionOk(sessionsSection)) return unknownLabel();
    return String(sessionsSection?.active_count ?? 0);
  });

  const auditEntries = computed(() => sections.value?.audit_log?.entries ?? []);

  /**
   * A failed audit-log read is not an empty audit log. Distinct from
   * `authFailed`, whose copy asserts the whole authdb is down — here the rest
   * of the grid is trustworthy and only this table is missing.
   */
  const auditLogUnavailableMessage = computed<string>(() =>
    t('web.admin.customers.detail.diagnostics.auditLog.unavailable', {
      reason: sections.value?.audit_log?.reason ?? unknownLabel(),
    })
  );
</script>

<template>
  <section
    class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
    data-testid="diagnostics-section">
    <div
      class="flex items-center justify-between gap-4 border-b border-gray-200 px-6 py-4 dark:border-gray-800">
      <h3 class="text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.customers.detail.diagnostics.title') }}
      </h3>
      <button
        type="button"
        data-testid="diagnostics-refresh"
        class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-blue-500 focus:outline-none disabled:opacity-50 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800"
        :disabled="loading"
        @click="load">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.customers.detail.retry') }}
      </button>
    </div>

    <!-- Load error (network/HTTP or contract mismatch). -->
    <div
      v-if="loadFailed"
      class="px-6 py-4"
      role="alert"
      data-testid="diagnostics-section-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.customers.detail.diagnostics.loadError') }}
      </span>
    </div>

    <div
      v-else-if="loading"
      class="px-6 py-8 text-center text-sm text-gray-500 dark:text-gray-400">
      {{ t('web.admin.customers.detail.diagnostics.loading') }}
    </div>

    <div
      v-else-if="sections"
      class="space-y-4 px-6 py-4">
      <!-- Findings: the triage summary. Healthy state when the list is empty. -->
      <div
        v-if="findings.length === 0"
        class="rounded-md border border-green-300 bg-green-50 px-4 py-3 text-sm text-green-800 dark:border-green-800 dark:bg-green-900/30 dark:text-green-200"
        data-testid="diagnostics-healthy">
        {{ t('web.admin.customers.detail.diagnostics.healthy') }}
      </div>
      <ul
        v-else
        class="space-y-2"
        data-testid="diagnostics-findings">
        <li
          v-for="finding in findings"
          :key="finding.code"
          class="flex items-start gap-2 rounded-md border px-4 py-3 text-sm"
          :class="CALLOUT_CLASSES[finding.severity]">
          <OIcon
            collection="heroicons"
            :name="CALLOUT_ICONS[finding.severity]"
            size="5"
            class="mt-0.5 shrink-0" />
          <span>
            <span class="font-mono text-xs font-semibold uppercase">{{ finding.code }}</span>
            — {{ finding.message }}
          </span>
        </li>
      </ul>

      <!-- The SQL-side sections below are skipped, say so once — and say WHICH
           of the two reasons applies (see authUnavailableMessage). -->
      <p
        v-if="authUnavailable"
        class="text-sm text-gray-500 italic dark:text-gray-400"
        data-testid="diagnostics-auth-unavailable">
        {{ authUnavailableMessage }}
      </p>

      <!-- Auth-state fact grid. -->
      <dl
        v-if="!authUnavailable"
        class="grid grid-cols-2 gap-x-6 gap-y-3 text-sm sm:grid-cols-4"
        data-testid="diagnostics-facts">
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.customers.detail.diagnostics.facts.authStatus') }}
          </dt>
          <dd
            class="mt-0.5 font-medium text-gray-900 dark:text-white"
            data-testid="diagnostics-fact-auth-status">
            {{ authStatusLabel }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.customers.detail.diagnostics.facts.password') }}
          </dt>
          <dd
            class="mt-0.5 font-medium text-gray-900 dark:text-white"
            data-testid="diagnostics-fact-password">
            {{ passwordLabel }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.customers.detail.diagnostics.facts.mfa') }}
          </dt>
          <dd class="mt-0.5 font-medium text-gray-900 dark:text-white">
            {{ mfaLabel }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.customers.detail.diagnostics.facts.loginFailures') }}
          </dt>
          <dd
            class="mt-0.5 font-medium text-gray-900 dark:text-white"
            data-testid="diagnostics-fact-login-failures">
            {{ loginFailuresLabel }}
            <span
              v-if="lockedOut"
              class="ml-1 inline-flex items-center rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700 dark:bg-red-900/40 dark:text-red-300">
              {{ t('web.admin.customers.detail.diagnostics.facts.lockedBadge') }}
            </span>
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.customers.detail.diagnostics.facts.rateLimiter') }}
          </dt>
          <dd
            class="mt-0.5 font-medium"
            :class="
              rateLimiterEngaged
                ? 'text-red-700 dark:text-red-300'
                : 'text-gray-900 dark:text-white'
            "
            data-testid="diagnostics-fact-rate-limiter">
            {{ rateLimiterLabel }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.customers.detail.diagnostics.facts.verification') }}
          </dt>
          <dd
            class="mt-0.5 font-medium text-gray-900 dark:text-white"
            data-testid="diagnostics-fact-verification">
            {{ verificationLabel }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.customers.detail.diagnostics.facts.sessions') }}
          </dt>
          <dd
            class="mt-0.5 font-medium text-gray-900 dark:text-white"
            data-testid="diagnostics-fact-sessions">
            {{ sessionsLabel }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.customers.detail.diagnostics.facts.lastLogin') }}
          </dt>
          <dd class="mt-0.5 font-medium text-gray-900 dark:text-white">
            {{ epochLabel(authAccount?.last_login_at) }}
          </dd>
        </div>
      </dl>

      <!-- Authentication log tail (Rodauth audit_logging, newest first). -->
      <div v-if="!authUnavailable">
        <h4 class="mb-2 text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.customers.detail.diagnostics.auditLog.title') }}
        </h4>
        <!-- "Could not read" and "nothing to read" are opposite conclusions. -->
        <p
          v-if="!sectionOk(sections.audit_log)"
          class="text-sm text-gray-500 dark:text-gray-400"
          data-testid="diagnostics-audit-log-unavailable">
          {{ auditLogUnavailableMessage }}
        </p>
        <p
          v-else-if="auditEntries.length === 0"
          class="text-sm text-gray-500 dark:text-gray-400"
          data-testid="diagnostics-audit-log-empty">
          {{ t('web.admin.customers.detail.diagnostics.auditLog.empty') }}
        </p>
        <div
          v-else
          class="overflow-x-auto">
          <table
            class="min-w-full divide-y divide-gray-200 text-sm dark:divide-gray-800"
            data-testid="diagnostics-audit-log">
            <tbody class="divide-y divide-gray-100 dark:divide-gray-800/60">
              <tr
                v-for="(entry, index) in auditEntries"
                :key="`${entry.at}-${index}`">
                <td class="py-1.5 pr-6 whitespace-nowrap text-gray-500 dark:text-gray-400">
                  {{ epochLabel(entry.at) }}
                </td>
                <td class="py-1.5 font-mono text-xs text-gray-700 dark:text-gray-300">
                  {{ entry.message }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </section>
</template>
