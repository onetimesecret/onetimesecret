// src/tests/apps/admin/AdminCustomerSessionsSection.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

const showMock = vi.fn();
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: showMock }),
}));

vi.mock('@/utils/format', () => ({
  formatDisplayDateTime: (d: Date) => `DT:${d.toISOString()}`,
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import AdminCustomerSessionsSection from '@/apps/admin/components/AdminCustomerSessionsSection.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const USER_ID = 'ur_abc123';

function sessionRow(overrides: Record<string, unknown> = {}) {
  return {
    session_id: 'sid_1',
    user_id: USER_ID,
    org_id: null,
    created_at: 1700000000,
    last_activity_at: 1700003600,
    ip_address: '203.0.113.7',
    user_agent: 'Mozilla/5.0',
    auth_method: 'password',
    mfa_used: null,
    ...overrides,
  };
}

function sessionsPayload(
  rows = [sessionRow(), sessionRow({ session_id: 'sid_2' })],
  currentSessionId: string | null = null
) {
  return {
    shrimp: '',
    record: {},
    details: { sessions: rows, count: rows.length, current_session_id: currentSessionId },
  };
}

const mountSection = () =>
  mount(AdminCustomerSessionsSection, {
    props: { userId: USER_ID },
    global: {
      plugins: [i18n],
      // The confirm dialogs (HeadlessUI) have their own spec; the badge/revoke
      // rendering under test lives in the table's actions cell.
      stubs: { AdminConfirmDialog: true },
    },
  });

const badge = (w: VueWrapper, sid: string) => w.find(`[data-testid="session-current-${sid}"]`);
const revoke = (w: VueWrapper, sid: string) => w.find(`[data-testid="session-revoke-${sid}"]`);

describe('AdminCustomerSessionsSection — current-session badge', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  afterEach(() => wrapper?.unmount());

  it('badges the matching row and withholds its revoke button', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, 'sid_1') });
    wrapper = mountSection();
    await flushPromises();

    // The colonel's own row: badge in, per-row revoke out (v-if/v-else).
    expect(badge(wrapper, 'sid_1').exists()).toBe(true);
    expect(revoke(wrapper, 'sid_1').exists()).toBe(false);
    expect(badge(wrapper, 'sid_1').text()).toContain(
      'web.admin.customers.detail.sessions.current.badge'
    );
    expect(badge(wrapper, 'sid_1').attributes('title')).toBe(
      'web.admin.customers.detail.sessions.current.tooltip'
    );
  });

  it('renders the revoke button (and no badge) on non-matching rows', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, 'sid_1') });
    wrapper = mountSection();
    await flushPromises();

    expect(revoke(wrapper, 'sid_2').exists()).toBe(true);
    expect(badge(wrapper, 'sid_2').exists()).toBe(false);
  });

  it('shows no badge and all revoke buttons when currentSessionId is null', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, null) });
    wrapper = mountSection();
    await flushPromises();

    // null must not accidentally match any row (the guard in isCurrentSession).
    expect(wrapper.find('[data-testid^="session-current-"]').exists()).toBe(false);
    expect(revoke(wrapper, 'sid_1').exists()).toBe(true);
    expect(revoke(wrapper, 'sid_2').exists()).toBe(true);
  });
});
