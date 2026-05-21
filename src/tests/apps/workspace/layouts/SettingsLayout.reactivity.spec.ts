// src/tests/apps/workspace/layouts/SettingsLayout.reactivity.spec.ts

import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createI18n } from 'vue-i18n';
import { defineComponent, h, nextTick } from 'vue';
import { setupTestPinia } from '@/tests/setup';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
import { authenticatedBootstrap } from '@/tests/fixtures/bootstrap.fixture';

// Mock vue-router. The RouterLink stub used by Vue Test Utils' default
// global stub renders as <router-link-stub> with no inspectable href, so we
// register an explicit <a data-tab-to> stub via mount(global.stubs) below.
vi.mock('vue-router', () => ({
  useRoute: () => ({ path: '/account/settings/profile' }),
}));

const RouterLinkStub = defineComponent({
  name: 'RouterLink',
  props: { to: { type: String, required: true } },
  setup(props, { slots, attrs }) {
    return () =>
      h(
        'a',
        { href: props.to, class: attrs.class as string, 'data-tab-to': props.to },
        slots.default?.()
      );
  },
});

// Mock OIcon
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: defineComponent({
    name: 'OIcon',
    props: ['collection', 'name'],
    template: '<span class="o-icon" />',
  }),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  // Fall back to the key path so tests can match on stable identifiers
  // (e.g. assertions check `data-tab-to` rather than label text).
  missingWarn: false,
  fallbackWarn: false,
  messages: { en: {} },
});

interface MountedLayout {
  wrapper: VueWrapper;
  store: ReturnType<typeof useBootstrapStore>;
}

async function mountLayout(initial: Parameters<ReturnType<typeof useBootstrapStore>['update']>[0]): Promise<MountedLayout> {
  await setupTestPinia();
  const store = useBootstrapStore();
  // Hydrate from the authenticated baseline, then layer the test's overrides
  // so each scenario only spells out what differs from a normal logged-in user.
  store.update({ ...authenticatedBootstrap, ...initial });
  const wrapper = mount(SettingsLayout, {
    global: {
      plugins: [i18n],
      stubs: { RouterLink: RouterLinkStub },
    },
  });
  await nextTick();
  return { wrapper, store };
}

function visibleTabIds(wrapper: VueWrapper): string[] {
  return wrapper
    .findAll('a[data-tab-to]')
    .map((a) => a.attributes('data-tab-to'))
    .filter((to): to is string => Boolean(to));
}

describe('SettingsLayout — reactive tab visibility', () => {
  let mounted: MountedLayout | null = null;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    mounted?.wrapper.unmount();
    mounted = null;
  });

  it('hides Security/Region/Caution for an SSO-only user (no password) on first mount', async () => {
    mounted = await mountLayout({
      authentication: { mode: 'full' },
      features: { mfa: true, webauthn: true, sso: { enabled: true }, restrict_to: null } as never,
      has_password: false,
    });
    const tabs = visibleTabIds(mounted.wrapper);

    // Profile and API tabs are always visible; the password-gated ones must not be.
    expect(tabs).toContain('/account/settings/profile');
    expect(tabs).toContain('/account/settings/api');
    expect(tabs).not.toContain('/account/settings/security');
    expect(tabs).not.toContain('/account/region');
    expect(tabs).not.toContain('/account/settings/caution');
  });

  it('reveals Security/Region/Caution after has_password flips without re-mounting', async () => {
    // Reproduces the reported bug: tabs stay hidden until full page reload.
    // After the snapshot+reactivity fix, a single store update should be enough.
    mounted = await mountLayout({
      authentication: { mode: 'full' },
      features: { mfa: true, webauthn: true, sso: { enabled: true }, restrict_to: null } as never,
      has_password: false,
    });

    expect(visibleTabIds(mounted.wrapper)).not.toContain('/account/settings/security');

    mounted.store.update({ has_password: true });
    await nextTick();

    const tabs = visibleTabIds(mounted.wrapper);
    expect(tabs).toContain('/account/settings/security');
    expect(tabs).toContain('/account/region');
    expect(tabs).toContain('/account/settings/caution');
  });

  it('keeps Security/Region/Caution hidden in SSO-only mode even when has_password is true', async () => {
    // Regression guard for the intentional SSO-only hiding behaviour: if a
    // platform forces `restrict_to=sso`, password-centric tabs must stay
    // hidden no matter what `has_password` says.
    mounted = await mountLayout({
      authentication: { mode: 'full' },
      features: {
        mfa: true,
        webauthn: true,
        sso: { enabled: true },
        restrict_to: 'sso',
      } as never,
      has_password: true,
    });
    const tabs = visibleTabIds(mounted.wrapper);

    expect(tabs).not.toContain('/account/settings/security');
    expect(tabs).not.toContain('/account/region');
    expect(tabs).not.toContain('/account/settings/caution');
  });
});
