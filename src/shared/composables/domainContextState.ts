// src/shared/composables/domainContextState.ts

import type { OrganizationPermissions } from '@/schemas/api/account/responses/permissions';
import { normalizeDomainHost } from '@/shared/utils/domain-host';
import { ref } from 'vue';

export const currentDomain = ref('');
export const confirmedOrganization = ref<OrganizationPermissions>();

/** Look up only the selected organization's current permissions snapshot. */
export function findSharingDomain(orgExtid?: string, host = currentDomain.value) {
  const org = confirmedOrganization.value;
  if (!org || org.extid !== orgExtid) return undefined;
  const normalized = normalizeDomainHost(host);
  return org.domains.find(domain => normalizeDomainHost(domain.display_domain) === normalized);
}
