// src/tests/apps/admin/AdminSystem.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
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

import AdminSystem from '@/apps/admin/views/AdminSystem.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const DB_URL = '/api/colonel/system/database';
const QUEUE_URL = '/api/colonel/queue';
const REDIS_URL = '/api/colonel/system/redis';

function dbPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      redis_info: {
        redis_version: '7.2.0',
        valkey_version: '8.0.1',
        server_name: 'valkey',
        redis_mode: 'standalone',
        os: 'Linux',
        uptime_in_seconds: 100000,
        uptime_in_days: 1,
        connected_clients: 5,
        total_commands_processed: 123456,
        instantaneous_ops_per_sec: 10,
      },
      database_sizes: { db0: { keys: 100, expires: 10, avg_ttl: 0 } },
      total_keys: 100,
      memory_stats: {
        used_memory: 1000,
        used_memory_human: '1.0M',
        used_memory_rss: 2000,
        used_memory_rss_human: '2.0M',
        used_memory_peak: 3000,
        used_memory_peak_human: '3.0M',
        mem_fragmentation_ratio: 1.5,
      },
      model_counts: { customers: 42, secrets: 100, receipts: 50 },
    },
  };
}

function queuePayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      connection: { connected: true, host: 'localhost:2121' },
      worker_health: { status: 'healthy', active_workers: 2 },
      queues: [{ name: 'mailer', pending_messages: 3, consumers: 1 }],
    },
  };
}

function redisPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      redis_info: { redis_version: '7.2.0', role: 'master' },
      timestamp: 1700000000,
    },
  };
}

/** Route each of the three independent single-GET read-outs by URL. */
function routeGet() {
  mockApi.get.mockImplementation((url: string) => {
    if (url === DB_URL) return Promise.resolve({ data: dbPayload() });
    if (url === QUEUE_URL) return Promise.resolve({ data: queuePayload() });
    if (url === REDIS_URL) return Promise.resolve({ data: redisPayload() });
    return Promise.reject(new Error(`unexpected GET ${url}`));
  });
}

// Stub the kit JsonViewer so the Redis section mounts without the CopyButton /
// clipboard machinery; expose the testid so the loaded branch is assertable.
const jsonViewerStub = {
  name: 'JsonViewer',
  template: '<div data-testid="system-redis-json" />',
  props: ['data', 'expandDepth', 'testid'],
};

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminSystem, {
    global: { plugins: [pinia, i18n], stubs: { JsonViewer: jsonViewerStub } },
  });

describe('AdminSystem (read-only status read-out — ticket #33)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  it('issues the three independent GETs on mount', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(DB_URL, undefined);
    expect(mockApi.get).toHaveBeenCalledWith(QUEUE_URL, undefined);
    expect(mockApi.get).toHaveBeenCalledWith(REDIS_URL, undefined);
  });

  it('renders the loaded database, queue and redis read-outs', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    // Database: model counts + engine version render straight from the record.
    const db = wrapper.find('[data-testid="system-database"]');
    expect(db.exists()).toBe(true);
    expect(wrapper.find('[data-testid="system-database-error"]').exists()).toBe(false);
    expect(db.text()).toContain('42'); // customers count
    expect(wrapper.find('[data-testid="server-version"]').text()).toContain('8.0.1');
    expect(wrapper.find('[data-testid="system-database-sizes"]').text()).toContain('db0');

    // Queue: connection host + per-queue row render.
    const queue = wrapper.find('[data-testid="system-queue"]');
    expect(queue.text()).toContain('localhost:2121');
    expect(wrapper.find('[data-testid="queue-table"]').text()).toContain('mailer');

    // Redis: the JsonViewer read-out mounts (loaded branch, not loading/error).
    expect(wrapper.find('[data-testid="system-redis-json"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="system-redis-error"]').exists()).toBe(false);
  });

  it('shows a per-section error state when each GET fails', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="system-database-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="system-queue-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="system-redis-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="system-redis-json"]').exists()).toBe(false);
  });

  it('shows the loading state while the requests are in flight', async () => {
    mockApi.get.mockReturnValue(new Promise(() => {})); // never resolves
    wrapper = mountView(pinia);

    // onMounted flips loading before the first await; a tick lets the render
    // reflect it. The GET never resolves, so loading persists.
    await flushPromises();
    expect(wrapper.find('[data-testid="system-database-loading"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="system-queue-loading"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="system-redis-loading"]').exists()).toBe(true);
  });
});
