// src/stores/index.ts

/**
 * Store Architecture
 *
 * Our stores directly handle both state management and API calls. While separate
 * service layers are common, we deliberately keep API calls in stores because:
 *
 * 1. Single Source of Truth
 *    - Stores ARE our service layer - they own both state and data fetching
 *    - Each store maps cleanly to a domain concept (Customer, Metadata, etc.)
 *    - Changes to API or state naturally live together
 *
 * 2. Schema Integration
 *    - Zod schemas handle validation, typing, and transformations
 *    - Schema system provides clear boundaries between API and store state
 *    - Type safety flows naturally from schema to store to components
 *
 * 3. Practical Benefits
 *    - No artificial abstraction layers or indirection
 *    - API calls are naturally scoped to their domain store
 *    - Clear patterns for error handling and loading states
 *    - Easy testing via direct API client mocking
 *
 * This architecture keeps our code focused and maintainable while providing
 * robust type safety and validation through our schema system.
 */

export { useAuthStore } from './authStore';
export { useBrandingStore } from './brandingStore';
export { useColonelStore } from './colonelStore';
export { useCsrfStore } from './csrfStore';
export { useCustomerStore } from './customerStore';
export { useDomainsStore } from './domainsStore';
export { useJurisdictionStore } from './jurisdictionStore';
export { useLanguageStore } from './languageStore';
export { useMetadataStore } from './metadataStore';
export { useNotificationsStore } from './notifications';
export { useSecretsStore } from './secretsStore';

// Plugin exports
export { logoutPlugin } from './plugins/logoutPlugin';
