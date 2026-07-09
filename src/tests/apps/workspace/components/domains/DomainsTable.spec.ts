// src/tests/apps/workspace/components/domains/DomainsTable.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import DomainsTable from '@/apps/workspace/components/domains/DomainsTable.vue';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

// Mock vue-router (RouterLink used for the add-domain link)
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/', query: {}, params: {} })),
  useRouter: vi.fn(() => ({ push: vi.fn() })),
  RouterLink: {
    name: 'RouterLink',
    template: '<a><slot /></a>',
    props: ['to'],
  },
}));

vi.mock('@vueuse/core', () => ({
  useConfirmDialog: () => ({
    isRevealed: { value: false },
    reveal: vi.fn(),
    confirm: vi.fn(),
    cancel: vi.fn(),
  }),
}));

vi.mock('@/shared/composables/useDomainsManager', () => ({
  useDomainsManager: () => ({ deleteDomain: vi.fn() }),
}));

vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({ can: () => true }),
}));

vi.mock('@/shared/composables/useOrgPermissions', () => ({
  useOrgPermissions: () => ({
    isOwnerOrAdmin: { value: true },
    canCreateDomain: { value: true },
  }),
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    getOrganizationByExtid: () => ({ extid: 'org_ext_123', current_user_role: 'owner' }),
  }),
}));

vi.mock('@/shared/stores/domainsStore', () => ({
  useDomainsStore: () => ({
    putHomepageConfig: vi.fn(),
  }),
}));

vi.mock('@/utils/features', () => ({
  isOrgsSsoEnabled: () => false,
  isOrgsCustomMailEnabled: () => false,
  isOrgsIncomingSecretsEnabled: () => true,
}));

vi.mock('@/apps/workspace/components/dashboard/DomainsTableDomainCell.vue', () => ({
  default: {
    name: 'DomainsTableDomainCell',
    template: '<div class="domain-cell" />',
    props: ['domain', 'orgid', 'canEmailConfig'],
  },
}));

vi.mock('@/apps/workspace/components/dashboard/DomainsTableActionsCell.vue', () => ({
  default: { name: 'DomainsTableActionsCell', template: '<div class="actions-cell" />' },
}));

vi.mock('@/shared/components/modals/ConfirmDialog.vue', () => ({
  default: { name: 'ConfirmDialog', template: '<div />' },
}));

vi.mock('@/shared/components/common/ToggleWithIcon.vue', () => ({
  default: {
    name: 'ToggleWithIcon',
    template: '<button type="button" class="toggle" @click="$emit(\'update:enabled\', !enabled)" />',
    props: ['enabled', 'disabled'],
    emits: ['update:enabled'],
  },
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span />', props: ['collection', 'name', 'class'] },
}));

const baseDomain = {
  extid: 'dm-test-extid',
  display_domain: 'test.example.com',
  verified: true,
};

function mountTable(domains: object[]) {
  return mount(DomainsTable, {
    props: {
      domains,
      isLoading: false,
      orgid: 'org_ext_123',
    },
  });
}

describe('DomainsTable - homepage incoming badge', () => {
  it('shows the badge when the homepage is enabled in incoming mode', () => {
    const wrapper = mountTable([
      { ...baseDomain, homepage_config: { enabled: true, secrets_mode: 'incoming' } },
    ]);
    expect(wrapper.find('[data-testid="homepage-incoming-badge"]').exists()).toBe(true);
  });

  it('hides the badge when secrets_mode is incoming but the homepage is disabled', () => {
    // Regression: merge semantics preserve secrets_mode while disabled, so a
    // domain can carry secrets_mode='incoming' with enabled=false. The badge
    // must not render for what is effectively a private homepage.
    const wrapper = mountTable([
      { ...baseDomain, homepage_config: { enabled: false, secrets_mode: 'incoming' } },
    ]);
    expect(wrapper.find('[data-testid="homepage-incoming-badge"]').exists()).toBe(false);
  });

  it('hides the badge when the homepage is enabled in create mode', () => {
    const wrapper = mountTable([
      { ...baseDomain, homepage_config: { enabled: true, secrets_mode: 'create' } },
    ]);
    expect(wrapper.find('[data-testid="homepage-incoming-badge"]').exists()).toBe(false);
  });
});
