// src/tests/apps/workspace/layouts/SettingsLayout.reactivity.spec.ts

import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, nextTick } from 'vue';
import { setupTestPinia } from '@/tests/setup';
import { createTestI18n } from '@tests/setup';
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

const i18n = createTestI18n();

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

  it('shows Security section in full-auth mode even without a password', async () => {
    mounted = await mountLayout({
      authentication: { mode: 'full' },
      features: { mfa: true, webauthn: true, sso: { enabled: true }, restrict_to: null } as never,
      has_password: false,
    });
    const tabs = visibleTabIds(mounted.wrapper);

    expect(tabs).toContain('/account/settings/profile');
    expect(tabs).toContain('/account/settings/api');
    expect(tabs).toContain('/account/settings/security');
  });

  it('hides Security section when auth mode is not full', async () => {
    mounted = await mountLayout({
      authentication: { mode: 'simple' },
      features: { mfa: true, webauthn: true, sso: { enabled: true }, restrict_to: null } as never,
      has_password: false,
    });
    const tabs = visibleTabIds(mounted.wrapper);

    expect(tabs).toContain('/account/settings/profile');
    expect(tabs).not.toContain('/account/settings/security');
  });

  it('reacts to auth mode change without re-mounting', async () => {
    mounted = await mountLayout({
      authentication: { mode: 'simple' },
      features: { mfa: true, webauthn: true, sso: { enabled: true }, restrict_to: null } as never,
      has_password: false,
    });

    expect(visibleTabIds(mounted.wrapper)).not.toContain('/account/settings/security');

    mounted.store.update({ authentication: { mode: 'full' } });
    await nextTick();

    expect(visibleTabIds(mounted.wrapper)).toContain('/account/settings/security');
  });
});
