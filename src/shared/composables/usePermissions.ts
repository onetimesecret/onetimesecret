import { type RoleCapability, isRoleCapability } from '@/schemas/contracts/authorization-registry';
import { toValue, type MaybeRefOrGetter } from 'vue';

type CapabilitySource = { status: string; role_capabilities?: readonly string[] };

/** A membership capability can be further limited by the target action's scope. */
export function usePermissions(membership: MaybeRefOrGetter<CapabilitySource | null | undefined>) {
  const hasCapability = (capability: RoleCapability): boolean => {
    const member = toValue(membership);
    return isRoleCapability(capability) && member?.status === 'active' &&
      member.role_capabilities?.includes(capability) === true;
  };
  return { hasCapability };
}
