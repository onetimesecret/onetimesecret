// src/tests/apps/admin/AdminUsage.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import AdminUsage from '@/apps/admin/views/AdminUsage.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const USAGE_URL = '/api/colonel/usage/export';

function usagePayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      date_range: { start_date: 1700000000, end_date: 1702592000, days: 30 },
      usage_data: {
        total_secrets: 1234,
        total_new_users: 56,
        secrets_by_state: { received: 800, viewed: 400, expired: 34 },
        avg_secrets_per_day: 41.1333,
        avg_users_per_day: 1.86,
      },
      secrets_by_day: { '2026-06-01': 10, '2026-06-02': 20 },
      users_by_day: { '2026-06-01': 1, '2026-06-02': 2 },
    },
  };
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminUsage, { global: { plugins: [pinia, i18n] } });

describe('AdminUsage (read-only metrics read-out — ticket #33)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  it('fetches the export with a date range on mount', async () => {
    mockApi.get.mockResolvedValue({ data: usagePayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledTimes(1);
    const [url, config] = mockApi.get.mock.calls[0];
    expect(url).toBe(USAGE_URL);
    // The default 30-day range is passed as Unix-second start/end params.
    expect(config).toBeDefined();
    expect(typeof config.params.start_date).toBe('number');
    expect(typeof config.params.end_date).toBe('number');
  });

  it('renders the loaded summary tiles, state breakdown and daily rows', async () => {
    mockApi.get.mockResolvedValue({ data: usagePayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    const content = wrapper.find('[data-testid="usage-content"]');
    expect(content.exists()).toBe(true);
    // Totals render straight from the record (localised number formatting).
    expect(wrapper.find('[data-testid="usage-total-secrets"]').text()).toContain('1,234');
    expect(wrapper.find('[data-testid="usage-new-users"]').text()).toContain('56');

    // Secrets-by-state chips.
    const byState = wrapper.find('[data-testid="usage-by-state"]');
    expect(byState.text()).toContain('received');
    expect(byState.text()).toContain('800');

    // Per-day tables.
    expect(wrapper.find('[data-testid="usage-secrets-by-day"]').text()).toContain('2026-06-01');
    expect(wrapper.find('[data-testid="usage-users-by-day"]').text()).toContain('2026-06-02');
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    const banner = wrapper.find('[data-testid="usage-error"]');
    expect(banner.exists()).toBe(true);
    expect(wrapper.find('[data-testid="usage-content"]').exists()).toBe(false);

    mockApi.get.mockResolvedValueOnce({ data: usagePayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="usage-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="usage-content"]').exists()).toBe(true);
  });

  it('disables the fetch button while a request is in flight', async () => {
    mockApi.get.mockReturnValue(new Promise(() => {})); // never resolves
    wrapper = mountView(pinia);

    // onMounted flips loading before the first await; a tick lets the render
    // reflect it. The GET never resolves, so loading persists.
    await flushPromises();
    expect(wrapper.find('[data-testid="usage-fetch"]').attributes('disabled')).toBeDefined();
  });

  // ---- File export (QA 2026-07-07: "Export" must download an actual file) --

  /** JSDOM's Blob has no .text(); go through FileReader instead. */
  function readBlobText(blob: Blob): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error);
      reader.readAsText(blob);
    });
  }

  /** JSDOM implements neither createObjectURL nor anchor-click navigation. */
  function stubDownloadPlumbing() {
    const createObjectURL = vi.fn((_blob: Blob) => 'blob:usage-export');
    const revokeObjectURL = vi.fn();
    Object.assign(URL, { createObjectURL, revokeObjectURL });
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    return { createObjectURL, revokeObjectURL, click };
  }

  afterEach(() => {
    delete (URL as unknown as Record<string, unknown>).createObjectURL;
    delete (URL as unknown as Record<string, unknown>).revokeObjectURL;
  });

  it('downloads the loaded payload as a real JSON file', async () => {
    mockApi.get.mockResolvedValue({ data: usagePayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    const { createObjectURL, revokeObjectURL, click } = stubDownloadPlumbing();
    await wrapper.find('[data-testid="usage-export-json"]').trigger('click');

    // A Blob was minted, an anchor download was clicked, and the URL released.
    expect(createObjectURL).toHaveBeenCalledTimes(1);
    const blob = createObjectURL.mock.calls[0][0];
    expect(blob.type).toBe('application/json');
    expect(JSON.parse(await readBlobText(blob)).usage_data.total_secrets).toBe(1234);

    expect(click).toHaveBeenCalledTimes(1);
    const anchor = click.mock.instances[0] as unknown as HTMLAnchorElement;
    expect(anchor.download).toMatch(/^usage-export_.*\.json$/);
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:usage-export');
  });

  it('downloads the day-by-day breakdown as CSV', async () => {
    mockApi.get.mockResolvedValue({ data: usagePayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    const { createObjectURL, click } = stubDownloadPlumbing();
    await wrapper.find('[data-testid="usage-export-csv"]').trigger('click');

    const blob = createObjectURL.mock.calls[0][0];
    expect(blob.type).toBe('text/csv');
    expect(await readBlobText(blob)).toBe(
      ['date,secrets,new_users', '2026-06-01,10,1', '2026-06-02,20,2'].join('\n')
    );
    const anchor = click.mock.instances[0] as unknown as HTMLAnchorElement;
    expect(anchor.download).toMatch(/^usage-export_.*\.csv$/);
  });
});
