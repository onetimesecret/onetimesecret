// src/shared/composables/useSharingControls.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { computed } from 'vue';

import { findSharingDomain } from './domainContextState';

export function useSharingControls(shareDomain?: () => string) {
  const bootstrap = useBootstrapStore();
  const organizations = useOrganizationStore();
  const selectedOrg = computed(() => organizations.currentOrganization ?? bootstrap.organization);
  const selectedDomain = computed(() =>
    findSharingDomain(selectedOrg.value?.extid, shareDomain?.()));
  const organization = computed(() => bootstrap.authenticated ? selectedOrg.value : undefined);
  const hostSnapshot = computed(() => bootstrap.secret_options?.host_sharing_policy);
  const knownHostOwner = computed(() => {
    const ownerId = hostSnapshot.value?.organization_extid;
    if (!bootstrap.authenticated || !ownerId) return undefined;
    if (organization.value?.extid === ownerId) return organization.value;
    return organizations.organizations?.find(org => org.extid === ownerId);
  });
  const hostPolicy = computed(() => {
    const host = hostSnapshot.value;
    const owner = knownHostOwner.value;
    if (host?.domain_passphrase_required === undefined || !owner?.sharing_policy ||
        owner.limits?.secret_lifetime == null) return host;

    // An owner edit updates the organization store while the request-host
    // snapshot still describes the policy at page load. The host domain can
    // independently require a passphrase even after its organization relaxes it.
    const domain = findSharingDomain(owner.extid, bootstrap.display_domain ?? '');
    return {
      ...owner.sharing_policy,
      passphrase_required: owner.sharing_policy.passphrase_required ||
        (domain?.passphrase_required ?? host.domain_passphrase_required),
      max_ttl: Math.min(owner.sharing_policy.max_ttl ?? Infinity,
        owner.limits.secret_lifetime > 0 ? owner.limits.secret_lifetime : Infinity),
    };
  });
  const policies = computed(() => [hostPolicy.value, organization.value?.sharing_policy]);
  const passphraseRequired = computed(() => Boolean(
    bootstrap.secret_options?.passphrase?.required ||
    selectedDomain.value?.passphrase_required ||
    policies.value.some(policy => policy?.passphrase_required)
  ));
  const recipientDomains = computed(() => {
    const lists = policies.value.flatMap(policy =>
      policy?.recipient_email_mode === 'restricted' && policy.recipient_email_domains
        ? [policy.recipient_email_domains] : []);
    if (!lists.length) return null;
    return lists[0].filter(domain => lists.every(list => list.includes(domain)));
  });
  const recipientEnabled = computed(() => bootstrap.uiCapabilities?.recipient !== false &&
    recipientDomains.value?.length !== 0 &&
    !policies.value.some(policy => policy?.recipient_email_mode === 'disabled'));
  const ttlCeiling = computed(() => {
    const ceilings = [
      bootstrap.authenticated
        ? organization.value?.limits?.secret_lifetime
        : bootstrap.secret_options?.ttl_max_anonymous,
      ...policies.value.map(policy => policy?.max_ttl),
    ].filter((limit): limit is number => typeof limit === 'number' && limit > 0 && Number.isFinite(limit));
    return ceilings.length ? Math.min(...ceilings) : null;
  });
  function clampTtl(value: number) {
    return Math.max(60, Math.min(value, ttlCeiling.value ?? Infinity, 31536000));
  }
  const defaultTtl = computed(() => clampTtl(bootstrap.secret_options?.default_ttl ?? 604800));

  return {
    passphraseRequired, recipientEnabled, recipientDomains, ttlCeiling, defaultTtl, clampTtl,
  };
}
