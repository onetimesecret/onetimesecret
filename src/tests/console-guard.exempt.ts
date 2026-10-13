// src/tests/console-guard.exempt.ts
//
// Spec files that src/tests/setup-console-guard.ts lets print to
// console.warn/console.error without failing. Every entry is debt from
// before the guard: fix the spec (make the expected output an assertion,
// or remove the warning's cause), then delete its line. New spec files do
// not go here.

export const CONSOLE_GUARD_EXEMPT: ReadonlySet<string> = new Set<string>([
  // A response fixture fails its schema, so the store or composable logs
  // "Schema validation failed for …". Correct the fixture, or, where the
  // test is about that failure, capture and assert the log.
  'src/tests/apps/admin/AdminBilling.spec.ts',
  'src/tests/apps/admin/AdminCustomerDetail.spec.ts',
  'src/tests/apps/admin/AdminCustomerDetailImpersonate.spec.ts',
  'src/tests/apps/admin/AdminCustomerDetailPurge.spec.ts',
  'src/tests/apps/admin/AdminCustomerDetailSetRole.spec.ts',
  'src/tests/apps/admin/AdminDomainToolbox.spec.ts',
  'src/tests/apps/admin/AdminOrganizationAddMember.spec.ts',
  'src/tests/apps/admin/AdminOrganizationDelete.spec.ts',
  'src/tests/apps/admin/AdminOrganizationDetail.spec.ts',
  'src/tests/apps/admin/ColonelAuditLog.spec.ts',
  'src/tests/apps/admin/DomainConfigsSection.spec.ts',
  'src/tests/apps/admin/StripeOrganizationsSection.spec.ts',
  'src/tests/apps/admin/useAdminBilling.spec.ts',
  'src/tests/apps/admin/useAdminCustomerSessions.spec.ts',
  'src/tests/apps/admin/useAdminCustomers.spec.ts',
  'src/tests/apps/admin/useAdminDlq.spec.ts',
  'src/tests/apps/admin/useAdminDomains.spec.ts',
  'src/tests/apps/admin/useAdminJobs.spec.ts',
  'src/tests/apps/admin/useColonelAuditLog.spec.ts',
  'src/tests/apps/admin/useOrganizationsList.spec.ts',
  'src/tests/apps/admin/usePaginatedFetch.spec.ts',
  'src/tests/apps/admin/useResourceFetch.spec.ts',
  'src/tests/services/signin-config.service.spec.ts',
  'src/tests/setup.harness.spec.ts',
  'src/tests/stores/identityStore.spec.ts',
  'src/tests/stores/incomingStore.spec.ts',
  'src/tests/stores/membersStore.spec.ts',
  'src/tests/stores/organizationStore.spec.ts',
  'src/tests/stores/receiptStore.spec.ts',
  'src/tests/stores/receiptStoreDateHandling.spec.ts',
  'src/tests/stores/secretStore.spec.ts',
  'src/tests/stores/secrets/secretStoreFieldHandling.spec.ts',

  // The code under test makes a request the spec does not mock
  // (axios-mock-adapter: "Could not find mock for"), and logs the failure.
  'src/tests/apps/admin/ElevationPrompt.spec.ts',
  'src/tests/apps/admin/useColonelElevation.spec.ts',
  'src/tests/apps/workspace/components/OrganizationContextBar.spec.ts',
  'src/tests/composables/useDomainContext.spec.ts',
  'src/tests/shared/components/modals/PlanPreviewModal.spec.ts',

  // An error path the test drives on purpose writes to console.error or
  // console.warn directly. Capture it with captureConsole() and assert on it
  // (or route the call through loggingService and use captureAppLogs()).
  'src/tests/apps/secret/support/Pricing.spec.ts',
  'src/tests/apps/workspace/billing/BillingOverview.spec.ts',
  'src/tests/apps/workspace/billing/CancelSubscriptionModal.spec.ts',
  'src/tests/apps/workspace/billing/CurrencyMigrationModal.spec.ts',
  'src/tests/apps/workspace/billing/InvoiceList.spec.ts',
  'src/tests/apps/workspace/billing/PlanChangeModal.spec.ts',
  'src/tests/composables/useDismissableBanner.spec.ts',
  'src/tests/composables/useEntitlements.spec.ts',
  'src/tests/shared/utils/dnsWidgetHtml.spec.ts',
  'src/tests/stores/bootstrapStore.accountTransition.spec.ts',
  'src/tests/stores/bootstrapStore.spec.ts',
  'src/tests/stores/domainsStore.spec.ts',
  'src/tests/stores/localReceiptStore.spec.ts',
  'src/tests/views/session/AcceptInvite.spec.ts',

  // "Locale … is not in available locales": under vitest, src/i18n.ts's
  // import.meta.glob('/../generated/locales/*.json') matches nothing (it is
  // relative to Vite's root, ./src), so the real i18n module has no locales.
  'src/tests/api/passiveRequest.spec.ts',
  'src/tests/apps/workspace/dashboard/passiveRefresh.spec.ts',
  'src/tests/stores/languageStore-locale-detection.spec.ts',
  'src/tests/stores/languageStore.spec.ts',

  // Setup patches auth fields through bootstrapStore.update(), which ignores
  // them and warns: the tests do not get the auth state they set up.
  'src/tests/apps/workspace/layouts/SettingsLayout.active-tab.spec.ts',
  'src/tests/apps/workspace/layouts/SettingsLayout.reactivity.spec.ts',

  // A locale message contains '<kind> <extid>', which vue-i18n reports as
  // HTML in every locale.
  'src/tests/i18n/admin-message-compile.spec.ts',

  // Prints a locale report on purpose.
  'src/tests/i18n/locale-consistency.spec.ts',
  'src/tests/i18n/naming-convention.spec.ts',

  // Warns when the production bundle has not been built (public/web/dist).
  'src/tests/apps/admin/admin-isolation.spec.ts',
]);
