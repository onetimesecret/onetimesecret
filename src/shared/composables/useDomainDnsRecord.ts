// src/shared/composables/useDomainDnsRecord.ts

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
 * The fields read from a domain record and from a domains API `cluster`.
 * Structural on purpose: the workspace passes the v3 CustomDomain and its
 * cluster, the Colonel its own detail record and cluster
 * (AdminDomainDnsDetails), and both must get the same answer.
 */
export interface DomainDnsRecordSource {
  is_apex?: boolean | null;
  trd?: string | null;
  base_domain?: string | null;
}

export interface DomainDnsClusterSource {
  validation_strategy?: string | null;
  proxy_ip?: string | null;
  proxy_host?: string | null;
}

/**
 * The address record (A / ALIAS / CNAME) that points a custom domain at this
 * install, as shown on the DomainVerify and DomainDns screens and in the
 * Colonel domain DNS panel.
 *
 * Where the record points depends on who terminates the traffic, not on
 * whether ownership is checked:
 *
 * - Approximated installs: the Approximated proxy. An apex domain gets an A
 *   record to `cluster.proxy_ip`, a subdomain a CNAME to `cluster.proxy_host`.
 * - Every other install ('caddy_on_demand', 'passthrough'): this install
 *   itself, by name — the canonical domain, falling back to the site host. An
 *   apex domain cannot hold a CNAME, so it gets ALIAS/ANAME. The backend
 *   exposes no address for these strategies. The Approximated proxy fields
 *   are never read here: they are empty on a fresh install, and after a move
 *   off 'approximated' they are still configured (for the orphaned-vhost
 *   chore) but no longer where a domain should point.
 *
 * The strategy is taken from the domains API `cluster` when the caller has
 * one (it describes the response being rendered), otherwise from the
 * bootstrap snapshot.
 */
export function useDomainDnsRecord(
  domain: MaybeRefOrGetter<DomainDnsRecordSource | null | undefined>,
  cluster?: MaybeRefOrGetter<DomainDnsClusterSource | null | undefined>
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
