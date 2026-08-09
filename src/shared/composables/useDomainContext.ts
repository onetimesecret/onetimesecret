// src/shared/composables/useDomainContext.ts

/**
 * Domain Context Composable
 *
 * Provides workspace-level domain context for managing secrets
 * across multiple custom domains. Domain context is a session-level filter
 * that determines which domain context is active for the current workspace.
 *
 * Domains are scoped to the currently active organization - when the user
 * switches organizations, the available domains list updates accordingly.
 *
 * @see docs/product/interaction-modes.md - Domain Context concept
 */

import { loggingService } from '@/services/logging.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useResourcePermissions } from '@/shared/composables/useResourcePermissions';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { normalizeDomainHost } from '@/shared/utils/domain-host';
import type { AxiosInstance } from 'axios';
import { computed, inject, ref, watch } from 'vue';

export interface DomainContext {
  /** The domain hostname (e.g., "acme.example.com" or "onetimesecret.com") */
  domain: string;
  /** The external ID for API calls (e.g., "cd1234abcdef") - undefined for canonical domain */
  extid: string | undefined;
  /** Display-friendly name for the context */
  displayName: string;
  /** Whether this is the canonical (default) domain */
  isCanonical: boolean;
}

// Shared state for domain context across components
const currentDomain = ref('');
const isInitialized = ref(false);
const isLoadingDomains = ref(false);

// AbortController for cancelling in-flight domain fetches during rapid org switches
let currentFetchController: AbortController | null = null;

// Track whether module-level watcher has been set up (only do once)
let watcherInitialized = false;

// Bootstrap store reference - initialized on first composable use
let bootstrapStoreInstance: ReturnType<typeof useBootstrapStore> | null = null;

// Domain data extracted from permissions API (replaces domainsStore for dropdown context)
const permissionsDomains = ref<Array<{ display_domain: string; extid: string }>>([]);
let permissionsInstance: ReturnType<typeof useResourcePermissions> | null = null;

/** Get bootstrap store instance (lazy singleton) */
function getBootstrapStore(): ReturnType<typeof useBootstrapStore> {
  if (!bootstrapStoreInstance) {
    bootstrapStoreInstance = useBootstrapStore();
  }
  return bootstrapStoreInstance;
}

/** Get permissions composable instance (lazy singleton, must be called during setup) */
function getPermissions(): ReturnType<typeof useResourcePermissions> {
  if (!permissionsInstance) {
    permissionsInstance = useResourcePermissions();
  }
  return permissionsInstance;
}

/** Get config values from bootstrap store (reads current values, normalized) */
function getConfig() {
  const store = getBootstrapStore();
  // canonical_domain is the canonical LINK domain (DEFAULT_DOMAIN, resolved
  // server-side as default||site.host). site_host is the app's own hostname
  // and may differ; fall back to it only for older bootstrap payloads.
  const canonicalDomain = normalizeDomainHost(store.canonical_domain || store.site_host);
  const pool = (store.link_domains ?? []).map(normalizeDomainHost).filter(Boolean);
  return {
    domainsEnabled: store.domains_enabled,
    canonicalDomain,
    // Operator link pool (LINK_DOMAINS, #4063): the domains offered in the
    // picker. The server always resolves an unset LINK_DOMAINS to
    // [canonical_domain] and fails boot when a configured pool names no
    // parseable host (Onetime::Config.validate_link_domains!), so an empty
    // array here means exactly one thing -- a stale pre-#4063 payload -- and
    // only then do we re-derive the canonical entry ourselves. canonicalDomain
    // is NOT guaranteed to be a member: the canonical host may be an internal
    // platform address the operator deliberately hides from the picker.
    linkDomains: pool.length ? pool : [canonicalDomain].filter(Boolean),
    serverDomainContext: normalizeDomainHost(store.domain_context),
    // Already display_domain values server-side; normalized anyway so the
    // membership tests below cannot depend on which side produced a string.
    customDomains: (store.custom_domains ?? []).map(normalizeDomainHost).filter(Boolean),
    // True when this page is being served from a tenant-branded host. Read
    // straight from domain_strategy, and NOT inferred from `display_domain !==
    // canonical_domain` the way the pre-#4063 code did: on an operator
    // link-pool host those two also differ, but the strategy is :canonical and
    // none of the branded-host rules apply. (domain_strategy is not surfaced
    // raw — this predicate is the only thing it is read for.)
    onCustomDomain: store.domain_strategy === 'custom',
    // The host actually serving this page. Only meaningful alongside
    // onCustomDomain, where it names the branded host and is the domain the
    // server anchors links on no matter what share_domain asks for.
    displayDomain: normalizeDomainHost(store.display_domain),
  };
}

/**
 * The link-pool entries actually offerable in the CURRENT browsing context.
 *
 * On a tenant-branded host the canonical domain is dropped. Selecting it there
 * is silently ignored end-to-end: process_share_domain nils out anchor hosts,
 * then determine_share_domain falls through to `display_domain if
 * custom_domain?` and anchors the link on the branded host anyway. Offering a
 * row whose selection the generated link contradicts is worse than not
 * offering it. (Pool members are NOT dropped -- v2 honors an authenticated
 * user's explicit pool selection from a branded host.)
 */
function getOfferableLinkDomains(): string[] {
  const { linkDomains, canonicalDomain, onCustomDomain } = getConfig();
  if (!onCustomDomain) return linkDomains;
  return linkDomains.filter((domain) => domain !== canonicalDomain);
}

/**
 * Preferred fallback drawn from the offerable link pool, for the paths that
 * have no user selection yet (currentContext before init, resetContext, and
 * the domains-disabled init branch).
 *
 * Canonical wins when it is offerable -- that keeps the historical "reset
 * returns you to the canonical domain" behavior -- otherwise the pool head.
 * Both are guaranteed members of availableDomains (buildAvailableDomains
 * appends every offerable pool entry), so setContext can round-trip the
 * result. Returns '' only when there is no offerable pool at all, which is the
 * one value the availableDomains invariant explicitly permits: the server
 * reads an empty share_domain as "no request" and anchors the link on
 * whichever host served the page.
 */
function getPoolFallbackDomain(): string {
  const { canonicalDomain } = getConfig();
  const offerable = getOfferableLinkDomains();
  if (canonicalDomain && offerable.includes(canonicalDomain)) return canonicalDomain;
  return offerable[0] ?? '';
}

/** Get display name for a given domain */
function getDomainDisplayName(domain: string): string {
  // Fall back to the pool, not canonicalDomain: naming the canonical host
  // here would surface an address the operator excluded from the picker.
  const name = domain || getPoolFallbackDomain();
  if (!name) {
    console.error('[useDomainContext] getDomainDisplayName called with no domain and an empty link pool');
  }
  return name || 'unknown';
}

/** Build available domains list from store */
function buildAvailableDomains(storeDomains: Array<{ display_domain: string }>): string[] {
  // Ordering contract: the org's custom domains first (permissions order),
  // then every OFFERABLE link-pool entry not already listed (pool order).
  // Every entry currentContext/resetContext/getPreferredDomain can produce
  // must appear here, because setContext silently rejects anything that does
  // not -- and nothing may appear here that the server would then ignore, see
  // getOfferableLinkDomains.
  const domainNames = storeDomains.map((d) => normalizeDomainHost(d.display_domain));
  getOfferableLinkDomains().forEach((domain) => {
    if (domain && !domainNames.includes(domain)) {
      domainNames.push(domain);
    }
  });
  return domainNames;
}

/** Get the preferred default domain (custom domain preferred over link pool) */
function getPreferredDomain(available: string[]): string {
  const { linkDomains } = getConfig();
  // Prefer the first entry the operator did NOT bless -- pool membership, not
  // "!== canonical", is what separates an operator entry from a customer's own
  // domain. The two sets can overlap (ConfigureDomains warns about, but does
  // not prevent, listing a registered CustomDomain in LINK_DOMAINS), so this
  // predicate is a sufficient test for "customer's domain" and not a necessary
  // one: an overlapping host fails it and falls to the tail.
  const customDomain = available.find((d) => !linkDomains.includes(d));
  // The tail is not a coin flip. buildAvailableDomains puts the org's domains
  // ahead of every pool entry, so `available[0]` is a customer domain whenever
  // the org has any, and the pool head only when it has none -- which is the
  // same answer the predicate would give. Never a value absent from
  // `available` -- setContext would drop it.
  return customDomain || available[0] || '';
}

/** Find extid for a given display_domain from store domains */
function findExtidByDomain(
  storeDomains: Array<{ display_domain: string; extid: string }>,
  domain: string
): string | undefined {
  // Both sides normalized: availableDomains entries have been through
  // normalizeDomainHost, so a raw comparison would miss on any host the
  // permissions API spelled differently (case, port).
  const target = normalizeDomainHost(domain);
  return storeDomains.find((d) => normalizeDomainHost(d.display_domain) === target)?.extid;
}

/** Find display_domain for a given extid from store domains */
function findDomainByExtid(
  storeDomains: Array<{ display_domain: string; extid: string }>,
  extid: string
): string | undefined {
  const found = storeDomains.find((d) => d.extid === extid)?.display_domain;
  // Normalized so the result round-trips through setContext, which tests
  // membership against the normalized availableDomains list.
  return found === undefined ? undefined : normalizeDomainHost(found);
}

/** Sync domain context to backend (fire-and-forget) */
async function syncDomainContextToServer(
  $api: AxiosInstance | undefined,
  domain: string
): Promise<void> {
  if (!$api) return;
  try {
    await $api.post('/api/account/update-domain-context', { domain });
  } catch (error) {
    console.warn('[useDomainContext] Failed to sync to server:', error);
  }
}

/**
 * Persist domain selection: registered custom domains and operator link-pool
 * entries sync to server + sessionStorage; everything else clears the session.
 *
 * The predicate is `custom_domains ∪ link_domains`, canonical domain INCLUDED.
 *
 * - Pool entries (LINK_DOMAINS, #4063) have no CustomDomain row and so are never
 *   in `custom_domains`. Gating on that list alone wrote nothing and synced
 *   nothing for them, so the picker silently reset on every reload.
 * - The server admits exactly this set: UpdateDomainContext#valid_domain?
 *   (apps/api/account/logic/account/update_domain_context.rb:93) accepts
 *   `DomainStrategy.canonical_host?(domain)` -- an exact match against the
 *   canonical set, which every pool member joined -- or the customer's own
 *   custom domains. A peer/sibling of a pool member matches neither list here
 *   and would be rejected there, so we must not persist it.
 * - The canonical domain used to be carved OUT of this set, on the reasoning
 *   that absent sessionStorage is itself the canonical/default state. That
 *   held only as long as nothing else remembered a selection. It does not:
 *   `sess['domain_context']` outlives sessionStorage and there is no endpoint
 *   that clears it, so selecting canonical dropped the local half of the
 *   preference while leaving the server half pointing at the previously
 *   selected custom domain -- and selectBestDomain reads the server half
 *   FIRST, so the next reload silently reverted the switch. Writing the
 *   canonical selection through both halves is what keeps them from diverging;
 *   it needs no clear path because there is no longer a selection that
 *   deliberately leaves one half stale.
 */
async function persistDomainContext(
  $api: AxiosInstance | undefined,
  domain: string,
  skipBackendSync: boolean
): Promise<void> {
  const { customDomains, linkDomains } = getConfig();
  if (customDomains.includes(domain) || linkDomains.includes(domain)) {
    sessionStorage.setItem('domainContext', domain);
    if (!skipBackendSync) await syncDomainContextToServer($api, domain);
  } else {
    // Unreachable from setContext (availableDomains gates it), and no longer
    // reachable from resetContext either now that the reset lands on the
    // served host. What is left is the pre-init tail with no domain at all,
    // where clearing is the only honest move: '' cannot be synced (the
    // endpoint rejects a blank domain outright), so writing it would leave the
    // two halves disagreeing rather than agreeing on "nothing".
    sessionStorage.removeItem('domainContext');
  }
}

/**
 * Resolve the active DomainContext from module state.
 *
 * Module-level rather than inline in the composable so the reactive read set
 * is identical for every caller (all state it touches is module-level too).
 */
function buildCurrentContext(): DomainContext {
  const { canonicalDomain } = getConfig();
  // Pre-init / anonymous callers land here. The fallback must be offerable:
  // SecretForm posts currentContext.domain as share_domain on every creation
  // (the anonymous homepage included), and guests may only name pool members.
  const domain = currentDomain.value || getPoolFallbackDomain();
  const isCanonical = domain === canonicalDomain;
  return {
    domain,
    extid: isCanonical ? undefined : findExtidByDomain(permissionsDomains.value, domain),
    displayName: getDomainDisplayName(domain),
    isCanonical,
  };
}

/**
 * Reset to the pool's preferred entry (canonical when it is offerable), never
 * to a canonical host the operator excluded from the picker.
 *
 * Goes through persistDomainContext rather than only clearing sessionStorage:
 * `sess['domain_context']` has no clear endpoint, so a local-only reset leaves
 * the server still naming the old selection and selectBestDomain restores it
 * on the next load. Writing the default through both halves IS the reset.
 *
 * On a branded host the pool fallback can be '' -- getOfferableLinkDomains
 * drops the canonical entry there, and with LINK_DOMAINS unset that is the
 * whole pool, which makes this the DEFAULT configuration rather than an edge
 * case. '' is not a resettable value: the endpoint rejects a blank domain
 * (UpdateDomainContext#field_specific_concerns), the rejection is swallowed by
 * syncDomainContextToServer's catch, and the server half would keep naming the
 * old selection for selectBestDomain to restore. So fall back to the host being
 * browsed instead. It is a value both halves accept -- it is one of the
 * customer's own custom domains, so valid_domain? admits it and it is already
 * in availableDomains -- and it is where determine_share_domain anchors links
 * from this host regardless of what share_domain asks for. "Reset to canonical"
 * was always fiction on a branded host; this is what actually happens.
 */
async function resetDomainContext($api: AxiosInstance | undefined): Promise<void> {
  const { onCustomDomain, displayDomain } = getConfig();
  const domain = getPoolFallbackDomain() || (onCustomDomain ? displayDomain : '');
  currentDomain.value = domain;
  await persistDomainContext($api, domain, false);
}

/**
 * Create domain fetcher using the permissions API.
 * Extracts domains for the current organization from the bulk permissions response.
 * @see src/tests/composables/useDomainContext.spec.ts
 */
function createPermissionsFetcher(
  organizationStore: ReturnType<typeof useOrganizationStore>,
) {
  return async (): Promise<boolean> => {
    const { domainsEnabled } = getConfig();
    if (!domainsEnabled) return true;
    const orgExtid = organizationStore.currentOrganization?.extid;
    if (!orgExtid) {
      console.debug('[useDomainContext] Skipping fetch: no currentOrganization set yet');
      return false;
    }

    if (currentFetchController) {
      currentFetchController.abort();
    }
    const controller = new AbortController();
    currentFetchController = controller;

    isLoadingDomains.value = true;
    try {
      const result = await permissionsInstance!.fetchAllPermissions();
      if (controller.signal.aborted) return false;

      const orgPerms = result?.organizations.find(o => o.extid === orgExtid);
      permissionsDomains.value = orgPerms?.domains ?? [];
      return true;
    } catch (error) {
      if (error instanceof Error && error.name !== 'AbortError') {
        console.warn('[useDomainContext] Failed to fetch permissions:', error);
      }
      return false;
    } finally {
      if (currentFetchController === controller) {
        isLoadingDomains.value = false;
        currentFetchController = null;
      }
    }
  };
}

/**
 * Select the best domain from available options.
 * Priority: server preference > sessionStorage > preferred domain (first custom or canonical)
 */
function selectBestDomain(available: string[]): string {
  const { serverDomainContext } = getConfig();
  // Normalized: a value stored by an older build (or by a server that kept the
  // configured spelling) must still match the normalized `available` list.
  const localContext = normalizeDomainHost(sessionStorage.getItem('domainContext'));

  if (serverDomainContext && available.includes(serverDomainContext)) {
    // Server-side preference takes priority
    sessionStorage.setItem('domainContext', serverDomainContext); // Sync sessionStorage
    return serverDomainContext;
  } else if (localContext && available.includes(localContext)) {
    // Fall back to sessionStorage if valid
    return localContext;
  } else {
    // Fall back to preferred domain (first custom domain or canonical)
    return getPreferredDomain(available);
  }
}

// Guard flag to prevent concurrent initialization attempts
let isInitializing = false;

/** Initialize domain context on module load (runs once). Returns promise for awaiting. */
async function initializeDomainContext(
  fetchFn: () => Promise<boolean | void>,
  getAvailable: () => string[]
): Promise<void> {
  if (isInitialized.value || isInitializing) return;

  isInitializing = true;
  const { domainsEnabled } = getConfig();

  try {
    if (domainsEnabled) {
      const fetchSucceeded = await fetchFn();
      if (fetchSucceeded) {
        // Only select domain if fetch succeeded (org was available)
        currentDomain.value = selectBestDomain(getAvailable());
        isInitialized.value = true;
      }
      // If fetch failed (no org yet), don't mark initialized - let watcher handle it
    } else {
      // Domains feature off: no permissions fetch, so the pool is the whole
      // of availableDomains. Land on a member of it, not on canonicalDomain.
      currentDomain.value = getPoolFallbackDomain();
      isInitialized.value = true;
    }
  } catch {
    // On error, don't mark initialized - allow retry via watcher
    console.warn('[useDomainContext] Initialization failed, will retry when org is available');
  } finally {
    // Always release the concurrency guard. The isInitialized ref tracks whether
    // initialization succeeded; isInitializing only prevents concurrent calls.
    isInitializing = false;
  }
}

/**
 * Composable for managing domain context in the workspace.
 * Domains are scoped to the current organization.
 */
export function useDomainContext() {
  const $api = inject('api') as AxiosInstance | undefined;
  const organizationStore = useOrganizationStore();
  getPermissions();

  // Type param omitted (buildAvailableDomains already returns string[])
  const availableDomains = computed(() => buildAvailableDomains(permissionsDomains.value));

  const fetchDomainsForOrganization = createPermissionsFetcher(organizationStore);

  // Set up module-level watcher ONCE to prevent multiple watchers racing
  if (!watcherInitialized) {
    watcherInitialized = true;
    watch(
      () => organizationStore.currentOrganization?.objid,
      async (newOrgId, oldOrgId) => {
        if (newOrgId && newOrgId !== oldOrgId) {
          const isCurrentRequest = await fetchDomainsForOrganization();
          if (!isCurrentRequest) return;
          if (!isInitialized.value) {
            currentDomain.value = selectBestDomain(availableDomains.value);
            isInitialized.value = true;
          } else if (currentDomain.value && !availableDomains.value.includes(currentDomain.value)) {
            currentDomain.value = getPreferredDomain(availableDomains.value);
          }
        }
      }
    );
  }

  const initPromise = initializeDomainContext(
    fetchDomainsForOrganization,
    () => availableDomains.value
  );

  const currentContext = computed<DomainContext>(buildCurrentContext);

  const setContext = async (domain: string, skipBackendSync = false): Promise<void> => {
    // Normalized first: availableDomains holds normalized hosts, so a raw host
    // from a caller (route param, stored preference) would be silently rejected.
    const selected = normalizeDomainHost(domain);
    if (!availableDomains.value.includes(selected)) return;
    currentDomain.value = selected;
    await persistDomainContext($api, selected, skipBackendSync);
  };

  /** Reverse lookup: find display_domain for a given extid */
  const getDomainByExtid = (extid: string): string | undefined =>
    findDomainByExtid(permissionsDomains.value, extid);

  /** Set domain context by extid (route param). Skips backend sync by default. */
  const setContextByExtid = async (extid: string, skipBackendSync = true): Promise<void> => {
    const domain = getDomainByExtid(extid);
    if (domain) await setContext(domain, skipBackendSync);
    else loggingService.debug(
      '[useDomainContext] No domain found for extid',
      { extid }
    );
  };

  return {
    currentContext,
    isContextActive: computed<boolean>(() => getConfig().domainsEnabled),
    hasMultipleContexts: computed<boolean>(() => availableDomains.value.length > 1),
    availableDomains,
    isLoadingDomains: computed(() => isLoadingDomains.value),
    setContext,
    resetContext: () => resetDomainContext($api),
    refreshDomains: fetchDomainsForOrganization,
    getDomainDisplayName,
    getExtidByDomain: (domain: string) => findExtidByDomain(permissionsDomains.value, domain),
    getDomainByExtid,
    setContextByExtid,
    initialized: initPromise,
  };
}

/**
 * Reset module-level state for testing purposes.
 * This is necessary because the composable uses singleton state.
 * @internal - Test use only
 */
export function __resetDomainContextForTesting(): void {
  currentDomain.value = '';
  isInitialized.value = false;
  isLoadingDomains.value = false;
  isInitializing = false;
  watcherInitialized = false;
  currentFetchController = null;
  bootstrapStoreInstance = null;
  permissionsDomains.value = [];
  permissionsInstance = null;
}
