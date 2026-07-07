// src/shared/stores/index.ts

// See store design docs in types/declarations/pinia.d.ts

export { useAccountStore } from './accountStore';
export { useAuthStore } from './authStore';
export { useBrandStore } from './brandStore';
export { useSystemSettingsStore } from './systemSettingsStore';
// NOTE: `useColonelInfoStore` is intentionally NOT re-exported here. This barrel
// is pulled into the isolated admin bundle (via `interceptors.ts`), and Pinia's
// `defineStore(...)` call sites are not tree-shaken away, so re-exporting the
// colonel store from the shared root would drag `colonelInfoStore.ts` into the
// admin chunk — violating the epic's hard bundle-isolation invariant (CONTRACT
// 6). Every consumer already imports it directly from
// `@/shared/stores/colonelInfoStore`; keep it that way.
export { useLocalReceiptStore } from './localReceiptStore';
export { useCsrfStore } from './csrfStore';
export { useCustomerStore } from './customerStore';
export { useDomainsStore } from './domainsStore';
export { useJurisdictionStore } from './jurisdictionStore';
export { useLanguageStore } from './languageStore';
export { useMembersStore } from './membersStore';
export { useReceiptListStore } from './receiptListStore';
export { useReceiptStore } from './receiptStore';
export { useNotificationsStore } from './notificationsStore';
export { useSecretStore } from './secretStore';
