// src/tests/apps/admin/AdminOverview.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, RouterLinkStub, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

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

import AdminOverview from '@/apps/admin/views/AdminOverview.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const STATS_URL = '/api/colonel/stats';
const TRENDS_URL = '/api/colonel/trends';
const INFO_URL = '/api/colonel/info';

function statsPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      counts: {
        customer_count: 1234,
        emails_sent: 55,
        receipt_count: 200,
        secret_count: 42,
        secrets_created: 9001,
        secrets_shared: 77,
        session_count: 17,
      },
    },
  };
}

function trendPoints(latestCount: number) {
  const points = [];
  for (let i = 0; i < 30; i++) {
    const day = new Date(Date.UTC(2026, 5, 9 + i)); // 2026-06-09 … 2026-07-08
    points.push({
      date: day.toISOString().slice(0, 10),
      count: i === 29 ? latestCount : 0,
    });
  }
  return points;
}

function trendsPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      days: 30,
      series: {
        signups: trendPoints(3),
        secrets_created: trendPoints(12),
      },
    },
  };
}

function infoPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      recent_customers: [],
      today_feedback: [{ msg: 'love the dark mode', stamp: 1700000000 }],
      yesterday_feedback: [],
      older_feedback: null,
      dbclient_info: '',
      billing_enabled: false,
      counts: {
        customer_count: 1234,
        emails_sent: 55,
        feedback_count: 8,
        receipt_count: 200,
        older_feedback_count: 0,
        recent_customer_count: 0,
        secret_count: 42,
        secrets_created: 9001,
        secrets_shared: 77,
        session_count: 17,
        today_feedback_count: 1,
        yesterday_feedback_count: 0,
      },
    },
  };
}

/** Route each of the three independent dashboard reads by URL. */
function routeGet(
  overrides: Partial<Record<string, () => Promise<{ data: unknown }>>> = {}
) {
  mockApi.get.mockImplementation((url: string) => {
    const custom = overrides[url];
    if (custom) return custom();
    if (url === STATS_URL) return Promise.resolve({ data: statsPayload() });
    if (url === TRENDS_URL) return Promise.resolve({ data: trendsPayload() });
    if (url === INFO_URL) return Promise.resolve({ data: infoPayload() });
    return Promise.reject(new Error(`unexpected GET ${url}`));
  });
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminOverview, {
    global: {
      plugins: [pinia, i18n],
      // StatCard tiles with a `to` render as router-links; the admin router
      // isn't mounted here, so use the slot-rendering official stub.
      stubs: { RouterLink: RouterLinkStub },
    },
  });

describe('AdminOverview (real dashboard — observability lane)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => {
    wrapper?.unmount();
  });

  it('fetches stats, trends and info in parallel on mount', async () => {
    routeGet();
    wrapper = mountView(pinia);

    // All three requests are issued before ANY response resolves (parallel,
    // not a waterfall).
    const urls = mockApi.get.mock.calls.map((c) => c[0]);
    expect(urls).toContain(STATS_URL);
    expect(urls).toContain(TRENDS_URL);
    expect(urls).toContain(INFO_URL);
    await flushPromises();
  });

  it('renders real stat tiles from the stats endpoint (incl. session_count)', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    const stats = wrapper.find('[data-testid="overview-stats"]');
    expect(stats.exists()).toBe(true);
    expect(stats.find('[data-testid="overview-stat-customers"]').text()).toContain('1,234');
    expect(stats.find('[data-testid="overview-stat-sessions"]').text()).toContain('17');
    expect(stats.find('[data-testid="overview-stat-secrets"]').text()).toContain('42');
    expect(stats.find('[data-testid="overview-stat-secretsCreated"]').text()).toContain('9,001');
  });

  it('no longer duplicates the sidebar: the body has no console-map nav grid', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    // The old launcher rendered one router-link per console section (13+).
    // The dashboard keeps only the stat-tile links.
    expect(wrapper.text()).not.toContain('web.admin.banner.title');
    expect(wrapper.text()).not.toContain('web.admin.domaintoolbox.title');
  });

  it('renders the 30-day sparklines with the latest value per series', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    const trends = wrapper.find('[data-testid="overview-trends"]');
    expect(trends.exists()).toBe(true);
    expect(trends.find('[data-testid="overview-sparkline-signups"]').exists()).toBe(true);
    expect(trends.find('[data-testid="overview-trend-signups"]').text()).toContain('3');
    expect(trends.find('[data-testid="overview-trend-secretsCreated"]').text()).toContain('12');
    // The forward-only collection caveat is always visible.
    expect(wrapper.text()).toContain('web.admin.overview.trends.collectingNote');
  });

  it('renders the feedback section bucketed today / yesterday / older', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    const feedback = wrapper.find('[data-testid="overview-feedback"]');
    expect(feedback.exists()).toBe(true);
    expect(feedback.find('[data-testid="overview-feedback-today"]').text()).toContain(
      'love the dark mode'
    );
    // Empty buckets render the empty message, not nothing.
    expect(feedback.find('[data-testid="overview-feedback-yesterday"]').text()).toContain(
      'web.admin.overview.feedback.empty'
    );
    expect(feedback.find('[data-testid="overview-feedback-older"]').exists()).toBe(true);
  });

  it('degrades per-section: a stats failure leaves trends + feedback rendering', async () => {
    routeGet({ [STATS_URL]: () => Promise.reject(new Error('boom')) });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="overview-stats-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="overview-trends"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="overview-feedback"]').exists()).toBe(true);
  });

  it('retries a failed section without remounting', async () => {
    routeGet({ [TRENDS_URL]: () => Promise.reject(new Error('boom')) });
    wrapper = mountView(pinia);
    await flushPromises();

    const banner = wrapper.find('[data-testid="overview-trends-error"]');
    expect(banner.exists()).toBe(true);

    routeGet(); // now succeed
    await banner.find('button').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="overview-trends-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="overview-trends"]').exists()).toBe(true);
  });

  it('is read-only: never fires a mutation', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.post).not.toHaveBeenCalled();
    expect(mockApi.delete).not.toHaveBeenCalled();
  });
});
