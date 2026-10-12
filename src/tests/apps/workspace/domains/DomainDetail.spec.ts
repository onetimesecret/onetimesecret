// src/tests/apps/workspace/domains/DomainDetail.spec.ts

import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import { onBeforeRouteLeave } from 'vue-router';
import DomainDetail from '@/apps/workspace/domains/DomainDetail.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/', query: {}, params: {} })),
  useRouter: vi.fn(() => ({ push: vi.fn() })),
  onBeforeRouteLeave: vi.fn(),
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

// Bypass Pinia's storeToRefs plumbing — feed it plain objects of refs.
vi.mock('pinia', () => ({
  storeToRefs: (store: Record<string, unknown>) => store,
}));

const mockDomain = ref<Record<string, unknown> | null>(null);
const mockInitialize = vi.fn();
const mockUpdateHomepageConfig = vi.fn();
const mockNotifyShow = vi.fn();

vi.mock('@/shared/composables/useDomain', () => ({
  useDomain: () => ({
    domain: mockDomain,
    isLoading: ref(false),
    initialize: mockInitialize,
  }),
}));

vi.mock('@/shared/composables/useDomainsManager', () => ({
  useDomainsManager: () => ({
    deleteDomain: vi.fn(),
    updateHomepageConfig: mockUpdateHomepageConfig,
  }),
}));

const mockCan = vi.fn((_entitlement: string) => true);

vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({ can: (entitlement: string) => mockCan(entitlement) }),
}));

vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: mockNotifyShow }),
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    organizations: ref([{ extid: 'org_ext_123', current_user_role: 'owner' }]),
  }),
}));

vi.mock('@/utils/features', () => ({
  isDomainOwnershipChecked: () => false,
  isOrgsCustomMailEnabled: () => false,
  isOrgsIncomingSecretsEnabled: () => true,
}));

vi.mock('@/apps/workspace/components/dashboard/DomainHeader.vue', () => ({
  default: { name: 'DomainHeader', template: '<div />', props: ['domain', 'hasUnsavedChanges', 'orgid', 'externalPath'] },
}));

vi.mock('@/shared/components/modals/ConfirmDialog.vue', () => ({
  default: { name: 'ConfirmDialog', template: '<div />' },
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span />', props: ['collection', 'name', 'class'] },
}));

vi.mock('@/apps/workspace/components/domains/DomainHomepageSelector.vue', () => ({
  default: {
    name: 'DomainHomepageSelector',
    template: '<div />',
    props: ['modelValue', 'disabled', 'incomingAvailable', 'incomingReady', 'incomingConfigRoute'],
  },
}));

function mountDetail() {
  return mount(DomainDetail, {
    props: { extid: 'dm-test-extid', orgid: 'org_ext_123' },
  });
}

describe('DomainDetail - homepage status line', () => {
  it('reports the incoming status when secrets_mode is incoming and ready', async () => {
    mockDomain.value = {
      homepage_config: { enabled: true, secrets_mode: 'incoming' },
      incoming_ready: true,
    };
    const wrapper = mountDetail();
    await wrapper.find('[data-testid="homepage-section-toggle"]').trigger('click');
    expect(wrapper.find('[data-testid="homepage-status"]').text()).toBe(
      'web.domains.homepage.status_incoming'
    );
  });

  it('degrades to the unready status when secrets_mode is incoming but incoming is not ready', async () => {
    // Regression: the stored choice can drift from what visitors actually see
    // (recipients removed elsewhere) — the backend fails closed to the
    // private trust card, so the status line must say so rather than
    // claiming the homepage is still interactive.
    mockDomain.value = {
      homepage_config: { enabled: true, secrets_mode: 'incoming' },
      incoming_ready: false,
    };
    const wrapper = mountDetail();
    await wrapper.find('[data-testid="homepage-section-toggle"]').trigger('click');
    expect(wrapper.find('[data-testid="homepage-status"]').text()).toBe(
      'web.domains.homepage.status_incoming_unready'
    );
  });

  it('reports the private status when the homepage is disabled', async () => {
    mockDomain.value = {
      homepage_config: { enabled: false, secrets_mode: 'incoming' },
      incoming_ready: false,
    };
    const wrapper = mountDetail();
    await wrapper.find('[data-testid="homepage-section-toggle"]').trigger('click');
    expect(wrapper.find('[data-testid="homepage-status"]').text()).toBe(
      'web.domains.homepage.status_private'
    );
  });
});

describe('DomainDetail - homepage save feedback', () => {
  beforeEach(() => {
    mockInitialize.mockReset();
    mockUpdateHomepageConfig.mockReset();
    mockNotifyShow.mockReset();
    mockDomain.value = {
      extid: 'dm-test-extid',
      homepage_config: { enabled: true, secrets_mode: 'create' },
      incoming_ready: false,
    };
  });

  // Mount, let the onMounted initialize() settle, then clear call history so
  // assertions only see what the save handler did.
  async function mountReady() {
    const wrapper = mountDetail();
    await flushPromises();
    mockInitialize.mockClear();
    mockUpdateHomepageConfig.mockClear();
    mockNotifyShow.mockClear();
    return wrapper;
  }

  async function selectHomepage(wrapper: ReturnType<typeof mountDetail>, choice: string) {
    await wrapper.find('[data-testid="homepage-section-toggle"]').trigger('click');
    await wrapper
      .findComponent({ name: 'DomainHomepageSelector' })
      .vm.$emit('update:modelValue', choice);
    await flushPromises();
  }

  it('shows the success toast once the post-save refetch lands', async () => {
    mockUpdateHomepageConfig.mockResolvedValue({ enabled: false });
    mockInitialize.mockResolvedValue(true);

    const wrapper = await mountReady();
    await selectHomepage(wrapper, 'private');

    expect(mockUpdateHomepageConfig).toHaveBeenCalledTimes(1);
    expect(mockInitialize).toHaveBeenCalledTimes(1);
    expect(mockNotifyShow).toHaveBeenCalledWith(
      'web.domains.homepage.update_success',
      'success',
      'top'
    );
  });

  it('suppresses the success toast when the refetch fails', async () => {
    // updateHomepageConfig succeeded, but initialize() swallowed an error and
    // returned undefined — a "saved" toast would contradict its error toast
    // and sit above a selector still showing the pre-change value.
    mockUpdateHomepageConfig.mockResolvedValue({ enabled: false });
    mockInitialize.mockResolvedValue(undefined);

    const wrapper = await mountReady();
    await selectHomepage(wrapper, 'private');

    expect(mockInitialize).toHaveBeenCalledTimes(1);
    expect(mockNotifyShow).not.toHaveBeenCalled();
  });

  it('neither refetches nor notifies when the update itself fails', async () => {
    mockUpdateHomepageConfig.mockResolvedValue(undefined);

    const wrapper = await mountReady();
    await selectHomepage(wrapper, 'private');

    expect(mockInitialize).not.toHaveBeenCalled();
    expect(mockNotifyShow).not.toHaveBeenCalled();
  });
});

describe('DomainDetail - unsaved network rules', () => {
  beforeEach(() => {
    mockDomain.value = {
      extid: 'dm-test-extid',
      homepage_config: {
        enabled: true,
        secrets_mode: 'create',
        allowed_cidrs: [],
        denied_cidrs: [],
      },
      incoming_ready: false,
    };
  });

  type LeaveGuard = (to: unknown, from: unknown, next: (arg?: boolean) => void) => void;

  function lastLeaveGuard(): LeaveGuard {
    const calls = vi.mocked(onBeforeRouteLeave).mock.calls;
    return calls[calls.length - 1][0] as unknown as LeaveGuard;
  }

  it('confirms before leaving while the network editor holds staged edits', async () => {
    const wrapper = mountDetail();
    await flushPromises();
    const guard = lastLeaveGuard();
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(false);

    await wrapper
      .findComponent({ name: 'DomainHomepageNetworkAccess' })
      .vm.$emit('update:dirty', true);
    const next = vi.fn();
    guard({}, {}, next);

    expect(confirmSpy).toHaveBeenCalledWith('web.domains.unsaved_changes_confirmation');
    expect(next).toHaveBeenCalledWith(false);
    expect(wrapper.findComponent({ name: 'DomainHeader' }).props('hasUnsavedChanges')).toBe(true);
    confirmSpy.mockRestore();
  });

  it('leaves without asking when nothing is staged', async () => {
    mountDetail();
    await flushPromises();
    const guard = lastLeaveGuard();
    const confirmSpy = vi.spyOn(window, 'confirm');

    const next = vi.fn();
    guard({}, {}, next);

    expect(confirmSpy).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith();
    confirmSpy.mockRestore();
  });
});

describe('DomainDetail - network rules entitlement', () => {
  beforeEach(() => {
    mockDomain.value = {
      extid: 'dm-test-extid',
      homepage_config: {
        enabled: true,
        secrets_mode: 'create',
        allowed_cidrs: ['10.0.0.0/8'],
        denied_cidrs: [],
      },
      incoming_ready: false,
    };
  });

  afterEach(() => {
    mockCan.mockImplementation(() => true);
  });

  it('locks the editor when the plan lacks homepage_network_rules', async () => {
    mockCan.mockImplementation((entitlement) => entitlement !== 'homepage_network_rules');
    const wrapper = mountDetail();
    await flushPromises();

    const editor = wrapper.findComponent({ name: 'DomainHomepageNetworkAccess' });
    expect(editor.props('locked')).toBe(true);
    // Stored rules stay enforced after a downgrade, so the badge stays too.
    expect(wrapper.find('[data-testid="homepage-network-badge"]').exists()).toBe(true);
  });

  it('unlocks the editor when the plan includes homepage_network_rules', async () => {
    const wrapper = mountDetail();
    await flushPromises();

    const editor = wrapper.findComponent({ name: 'DomainHomepageNetworkAccess' });
    expect(editor.props('locked')).toBe(false);
  });
});
