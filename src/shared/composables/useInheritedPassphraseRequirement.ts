// src/shared/composables/useInheritedPassphraseRequirement.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { computed } from 'vue';

/** The level above a settings form that already requires a passphrase. */
export type InheritedPassphraseRequirement = 'instance' | 'organization' | null;

/**
 * Whether a level above a "require a passphrase" setting already requires
 * one, so the form can show its own checkbox as on and locked instead of
 * as a choice that has no effect.
 *
 * The server ORs the levels (Onetime::SecretSharingPolicy#passphrase_required?):
 * the installation's `site.secret_options.passphrase.required`, then the
 * organization's sharing controls. This reads the same two values from what
 * the client already has: the bootstrap payload and the organization store.
 *
 * @param organizationExtid - the organization above the setting, for a
 *   domain-level form. Omit for the organization's own form, where only the
 *   installation is above it. An organization the store has not loaded
 *   counts as not requiring one.
 */
export function useInheritedPassphraseRequirement(organizationExtid?: () => string | undefined) {
  const bootstrap = useBootstrapStore();
  const organizations = useOrganizationStore();

  return computed<InheritedPassphraseRequirement>(() => {
    if (bootstrap.secret_options?.passphrase?.required) return 'instance';

    const extid = organizationExtid?.();
    if (!extid) return null;
    const current = organizations.currentOrganization;
    const organization =
      organizations.organizations?.find((org) => org.extid === extid) ??
      (current?.extid === extid ? current : undefined);
    return organization?.sharing_policy?.passphrase_required ? 'organization' : null;
  });
}
