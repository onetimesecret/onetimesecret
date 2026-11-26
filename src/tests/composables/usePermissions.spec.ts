import { ref } from 'vue';
import { describe, expect, it } from 'vitest';
import { useFeatures } from '@/shared/composables/useFeatures';
import { usePermissions } from '@/shared/composables/usePermissions';

describe('organization features and membership capabilities', () => {
  it('prefers an explicit empty feature list and reads features from older organization responses', () => {
    const source = ref<{ entitlements: string[]; plan_entitlements?: string[] }>({
      entitlements: ['incoming_secrets', 'manage_org'],
    });
    const { hasFeature } = useFeatures(source);
    expect(hasFeature('incoming_secrets')).toBe(true);
    source.value.plan_entitlements = [];
    expect(hasFeature('incoming_secrets')).toBe(false);
    // @ts-expect-error A string received from an untyped caller is also checked at runtime.
    expect(hasFeature('manage_org')).toBe(false);
  });

  it('requires the active member capability field even when legacy data includes manage_org', () => {
    const source = ref<{ status: string; entitlements: string[]; role_capabilities?: string[] }>({
      status: 'active', entitlements: ['manage_org'],
    });
    const { hasCapability } = usePermissions(source);
    expect(hasCapability('manage_org')).toBe(false);
    source.value.role_capabilities = ['manage_org'];
    expect(hasCapability('manage_org')).toBe(true);
    source.value.status = 'pending';
    expect(hasCapability('manage_org')).toBe(false);
    source.value.status = 'active';
    source.value.role_capabilities = [];
    expect(hasCapability('manage_org')).toBe(false);
  });
});
