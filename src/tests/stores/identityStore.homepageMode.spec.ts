// src/tests/stores/identityStore.homepageMode.spec.ts
//
// Reactivity contract for identityStore's homepage secrets mode and the
// allowPublicHomepage watch.
//
// The subtle case both pin: pinia's $patch deep-merges a nested plain
// object IN PLACE (same object reference), so a shallow watch on
// homepage_config only fires on the null -> object transition. On custom
// domains bootstrap always ships an object, so in-session updates (an
// admin changing the homepage from the workspace) must still propagate —
// homepageSecretsMode is a computed for exactly this reason, and the
// allowPublicHomepage watch is deep.

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { nextTick } from 'vue';
import { createPinia, setActivePinia } from 'pinia';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapSnapshot: vi.fn(() => null),
  updateBootstrapSnapshot: vi.fn(),
  _resetForTesting: vi.fn(),
}));

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useProductIdentity } from '@/shared/stores/identityStore';
import type { HomepageConfigCanonical } from '@/schemas/contracts/custom-domain/homepage-config';

function homepageConfig(
  overrides: Partial<HomepageConfigCanonical> = {}
): HomepageConfigCanonical {
  return {
    domain_id: 'd_123',
    enabled: true,
    secrets_mode: 'create',
    signup_enabled: false,
    signin_enabled: false,
    disabled_homepage_variant: null,
    created_at: 1700000000,
    updated_at: 1700000000,
    ...overrides,
  };
}

describe('identityStore homepage secrets mode', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('defaults to create when homepage_config is null (canonical domain)', () => {
    const identity = useProductIdentity();
    expect(identity.homepageSecretsMode).toBe('create');
  });

  it('reads the mode from bootstrap homepage_config', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ homepage_config: homepageConfig({ secrets_mode: 'incoming' }) });

    const identity = useProductIdentity();
    expect(identity.homepageSecretsMode).toBe('incoming');
    expect(identity.allowPublicHomepage).toBe(true);
  });

  it('tracks an in-place $patch of an existing homepage_config object', async () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ homepage_config: homepageConfig() });

    const identity = useProductIdentity();
    expect(identity.homepageSecretsMode).toBe('create');

    // Same nested object reference after this $patch — pinia merges in
    // place. The computed must still see the change.
    bootstrap.$patch({ homepage_config: homepageConfig({ secrets_mode: 'incoming' }) });
    await nextTick();

    expect(identity.homepageSecretsMode).toBe('incoming');
  });

  it('propagates an in-place enabled flip to allowPublicHomepage (deep watch)', async () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ homepage_config: homepageConfig({ enabled: true }) });

    const identity = useProductIdentity();
    expect(identity.allowPublicHomepage).toBe(true);

    bootstrap.$patch({ homepage_config: homepageConfig({ enabled: false }) });
    await nextTick();

    expect(identity.allowPublicHomepage).toBe(false);
  });
});
