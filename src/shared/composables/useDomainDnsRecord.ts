// src/shared/composables/useDomainDnsRecord.ts

import type { CustomDomainProxy } from '@/schemas/api/v3/responses/domains';
import type { CustomDomain } from '@/schemas/shapes/v3/custom-domain';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import {
  isApproximatedDomainValidation,
  isApproximatedDomainValidationOf,
} from '@/utils/features';
import { storeToRefs } from 'pinia';
import { computed, type MaybeRefOrGetter, toValue } from 'vue';

/** Which address record the customer is asked to create. */
export type DomainDnsRecordKind = 'a' | 'alias' | 'cname';

/**
 * The address record (A / ALIAS / CNAME) that points a custom domain at this
 * install, as shown on the DomainVerify and DomainDns screens.
 *
 * Where the record points depends on who terminates the traffic, not on
 * whether ownership is checked:
 *
 * - Approximated installs: the Approximated proxy. An apex domain gets an A
 *   record to `cluster.proxy_ip`, a subdomain a CNAME to `cluster.proxy_host`.
 * - Every other install ('caddy_on_demand', 'passthrough'): this install
 *   itself, by name — the canonical domain, falling back to the site host. An
 *   apex domain cannot hold a CNAME, so it gets ALIAS/ANAME. The backend
 *   exposes no address for these strategies and the Approximated proxy
 *   fields are empty, so they are never read here.
 *
 * The strategy is taken from the domains API `cluster` when the caller has
 * one (it describes the response being rendered), otherwise from the
 * bootstrap snapshot.
 */
export function useDomainDnsRecord(
  domain: MaybeRefOrGetter<CustomDomain | null | undefined>,
  cluster?: MaybeRefOrGetter<CustomDomainProxy | null | undefined>
) {
  const { canonical_domain, site_host } = storeToRefs(useBootstrapStore());

  const isApex = computed(() => toValue(domain)?.is_apex ?? false);

  const usesApproximatedProxy = computed(() => {
    const c = toValue(cluster);
    return c ? isApproximatedDomainValidationOf({ domains: c }) : isApproximatedDomainValidation();
  });

  const kind = computed<DomainDnsRecordKind>(() => {
    if (!isApex.value) return 'cname';
    return usesApproximatedProxy.value ? 'a' : 'alias';
  });

  const recordType = computed(() => {
    if (kind.value === 'a') return 'A';
    return kind.value === 'alias' ? 'ALIAS / ANAME' : 'CNAME';
  });

  // '@' at the zone root for apex domains, otherwise the subdomain label.
  // Keyed on is_apex — not trd's truthiness — so a blank trd on a non-apex
  // record doesn't silently read '@'.
  const recordHost = computed(() => (isApex.value ? '@' : toValue(domain)?.trd || '@'));

  // The base domain for context. Apex has no leading dot ('@' + example.com);
  // a subdomain gets the dotted form (test + .example.com).
  const recordHostAppendix = computed(() => {
    const base = toValue(domain)?.base_domain;
    if (!base) return '';
    return isApex.value ? base : `.${base}`;
  });

  const recordTarget = computed(() => {
    if (usesApproximatedProxy.value) {
      const c = toValue(cluster);
      return (isApex.value ? c?.proxy_ip : c?.proxy_host) ?? '';
    }
    return canonical_domain.value || site_host.value || '';
  });

  return {
    isApex,
    usesApproximatedProxy,
    kind,
    recordType,
    recordHost,
    recordHostAppendix,
    recordTarget,
  };
}
