// src/shared/composables/useInheritedPassphraseRequirement.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { computed } from 'vue';

/** The level above a settings form that already requires a passphrase. */
export type InheritedPassphraseRequirement = 'instance' | 'organization' | 'domain' | null;

/**
 * Whether a level above a "require a passphrase" setting already requires
 * one, so the form can show its own checkbox as on and locked instead of
 * as a choice that has no effect.
 *
 * The server ORs the levels (Onetime::SecretSharingPolicy#passphrase_required?):
 * the installation's `site.secret_options.passphrase.required`, the
 * organization's sharing controls, then the custom domain's own brand
 * setting. This reads the same values from what the client already has:
 * the bootstrap payload, the organization store and the loaded domain.
 *
 * @param organizationExtid - the organization above the setting, for a
 *   domain-level form. Omit for the organization's own form, where only the
 *   installation is above it. An organization the store has not loaded
 *   counts as not requiring one.
 * @param domainRequires - for a domain's incoming secrets form: whether the
 *   domain's brand settings require a passphrase. Incoming secrets go
 *   through the same policy with that domain, so it binds them too.
 */
export function useInheritedPassphraseRequirement(
  organizationExtid?: () => string | undefined,
  domainRequires?: () => boolean | undefined
) {
  const bootstrap = useBootstrapStore();
  const organizations = useOrganizationStore();

  const organizationRequires = (extid: string | undefined): boolean => {
    if (!extid) return false;
    const current = organizations.currentOrganization;
    const organization =
      organizations.organizations?.find((org) => org.extid === extid) ??
      (current?.extid === extid ? current : undefined);
    return !!organization?.sharing_policy?.passphrase_required;
  };

  return computed<InheritedPassphraseRequirement>(() => {
    if (bootstrap.secret_options?.passphrase?.required) return 'instance';
    if (organizationRequires(organizationExtid?.())) return 'organization';
    return domainRequires?.() ? 'domain' : null;
  });
}
