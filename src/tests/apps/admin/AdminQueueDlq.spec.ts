// src/tests/apps/admin/AdminQueueDlq.spec.ts

import { AxiosError } from 'axios';
import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/** Build a real AxiosError so the shared classifier extracts `data.error`. */
function axiosError(status: number, data: unknown, message = 'Request failed'): AxiosError {
  const err = new AxiosError(message);
  err.response = { status, data, statusText: '', headers: {}, config: {} as never };
  return err;
}

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

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

// Render the HeadlessUI dialog markup synchronously (mirrors AdminSessions.spec).
vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog" @close="$emit(\'close\')"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel" :data-testid="$attrs[\'data-testid\']"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: { name: 'DialogTitle', template: '<h3><slot /></h3>', props: ['as', 'class'] },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: { name: 'TransitionChild', template: '<div><slot /></div>', props: ['as'] },
}));

import AdminQueueDlq from '@/apps/admin/views/AdminQueueDlq.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const LIST_URL = '/api/colonel/queues/dlq';
const QUEUE = 'dlq.billing.event';
const SHORT = 'billing.event';
const DETAIL_URL = `${LIST_URL}/${QUEUE}`;

function dlqRow(overrides: Record<string, unknown> = {}) {
  return { queue: QUEUE, messages: 3, consumers: 1, ...overrides };
}

function listPayload(rows = [dlqRow()]) {
  return {
    shrimp: '',
    record: {},
    details: {
      dlqs: rows,
      pagination: { page: 1, per_page: 50, total_count: rows.length, total_pages: 1 },
      connected: true,
    },
  };
}

function messagesPayload() {
  return {
    shrimp: '',
    record: { queue: QUEUE, total_messages: 3, showing: 1 },
    details: {
      messages: [
        {
          delivery_tag: 1,
          message_id: 'm1',
          timestamp: 1700000000,
          age: '1m ago',
          original_queue: 'billing.event.process',
          death_reason: 'rejected',
          death_count: 2,
          error: null,
          content_type: 'application/json',
          payload_preview: '{"n":1}',
        },
      ],
    },
  };
}

function replayAck() {
  return {
    shrimp: '',
    record: { queue: QUEUE, replayed: 3, failed: 0, would_replay: 0, dry_run: false },
    details: { message: 'Replayed 3 message(s), 0 failed', errors: [] },
  };
}

function replayDryRunAck() {
  return {
    shrimp: '',
    record: { queue: QUEUE, replayed: 0, failed: 0, would_replay: 3, dry_run: true },
    details: { message: '3 message(s) would be replayed', errors: [] },
  };
}

/** Route the replay POST by its `dry_run` flag: preview vs live. */
function routeReplayPost() {
  mockApi.post.mockImplementation((url: string, body: { dry_run?: boolean } = {}) => {
    if (url === `${DETAIL_URL}/replay`) {
      return Promise.resolve({ data: body.dry_run ? replayDryRunAck() : replayAck() });
    }
    return Promise.reject(new Error(`unexpected POST ${url}`));
  });
}

function purgeAck() {
  return {
    shrimp: '',
    record: { queue: QUEUE, count: 3, purged: 3, dry_run: false },
    details: { message: 'Purged 3 message(s)' },
  };
}

/** Route GET by url so list + detail can both be mocked in one mount. */
function routeGet(detail = messagesPayload(), list = listPayload()) {
  mockApi.get.mockImplementation((url: string) => {
    if (url === LIST_URL) return Promise.resolve({ data: list });
    if (url === DETAIL_URL) return Promise.resolve({ data: detail });
    return Promise.reject(new Error(`unexpected GET ${url}`));
  });
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminQueueDlq, { global: { plugins: [pinia, i18n] } });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');
const listGetCount = () => mockApi.get.mock.calls.filter((c) => c[0] === LIST_URL).length;

describe('AdminQueueDlq (list + inspect + guarded replay/purge — ticket #42)', () => {
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

  // ---- List -----------------------------------------------------------------

  it('fetches the DLQ page on mount and renders a row per queue', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(LIST_URL, { params: { page: 1, per_page: 50 } });
    const table = wrapper.find('[data-testid="dlq-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain(SHORT);
    expect(table.text()).toContain('3'); // message count
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    const banner = wrapper.find('[data-testid="dlq-error"]');
    expect(banner.exists()).toBe(true);

    routeGet();
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="dlq-error"]').exists()).toBe(false);
  });

  // ---- Inspect drawer -------------------------------------------------------

  it('opens the detail drawer on row click and peeks the messages', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="dlq-table"] tbody tr').trigger('click');
    await flushPromises();

    expect(mockApi.get.mock.calls.some((c) => c[0] === DETAIL_URL)).toBe(true);
    const content = wrapper.find('[data-testid="dlq-drawer-content"]');
    expect(content.exists()).toBe(true);
    expect(content.text()).toContain('m1'); // message id
    expect(content.text()).toContain('billing.event.process'); // original queue
  });

  // ---- Broker connectivity --------------------------------------------------

  it('renders the disconnected notice when the broker is unreachable (connected:false)', async () => {
    const list = listPayload([]);
    list.details.connected = false;
    routeGet(messagesPayload(), list);
    wrapper = mountView(pinia);
    await flushPromises();

    // The store must surface `connected`, not drop it — otherwise an unreachable
    // broker is indistinguishable from a healthy empty DLQ set.
    expect(wrapper.find('[data-testid="dlq-disconnected"]').exists()).toBe(true);
  });

  // ---- Guarded replay (dry-run preview → explicit live confirm) --------------

  it('previews replay as a dry-run first, then replays live on explicit confirm', async () => {
    routeGet();
    routeReplayPost();
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await wrapper.find(`[data-testid="replay-${SHORT}"]`).trigger('click');
    await flushPromises();

    // First step is the safe dry-run preview (no republish).
    expect(mockApi.post).toHaveBeenCalledWith(`${DETAIL_URL}/replay`, { dry_run: true });
    // Replay is low-risk: no typed-confirmation input, submit enabled immediately.
    expect(dialogInput(wrapper).exists()).toBe(false);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

    // Explicit second step: the LIVE replay.
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(`${DETAIL_URL}/replay`, { dry_run: false });
    expect(showMock).toHaveBeenCalledWith('web.admin.queue.replay.success', 'success');
    expect(listGetCount()).toBe(before + 1);
  });

  it('surfaces a dry-run preview failure and does NOT open the live-replay confirm', async () => {
    routeGet();
    mockApi.post.mockRejectedValue(axiosError(422, { error: 'Message queue is not connected' }));
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find(`[data-testid="replay-${SHORT}"]`).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="dlq-replay-preview-error"]').text()).toContain(
      'Message queue is not connected'
    );
    // The live-replay confirm never opened, so no live replay was issued.
    expect(dialogSubmit(wrapper).exists()).toBe(false);
    const liveReplays = mockApi.post.mock.calls.filter(
      (c) => c[0] === `${DETAIL_URL}/replay` && c[1]?.dry_run === false
    );
    expect(liveReplays).toHaveLength(0);
    expect(showMock).not.toHaveBeenCalled();
  });

  // ---- Guarded purge (typed-confirmation) -----------------------------------

  it('gates purge behind typed-confirmation of the queue name', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find(`[data-testid="purge-${SHORT}"]`).trigger('click');
    await flushPromises();

    expect(dialogInput(wrapper).exists()).toBe(true);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

    await dialogInput(wrapper).setValue('wrong');
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

    await dialogInput(wrapper).setValue(SHORT);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('POSTs the purge, notifies and refreshes on confirm', async () => {
    routeGet();
    mockApi.post.mockResolvedValue({ data: purgeAck() });
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await wrapper.find(`[data-testid="purge-${SHORT}"]`).trigger('click');
    await dialogInput(wrapper).setValue(SHORT);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(`${DETAIL_URL}/purge`, {});
    expect(showMock).toHaveBeenCalledWith('web.admin.queue.purge.success', 'success');
    expect(dialogInput(wrapper).exists()).toBe(false);
    expect(listGetCount()).toBe(before + 1);
  });

  it('does NOT purge when submitted without a matching token', async () => {
    routeGet();
    mockApi.post.mockResolvedValue({ data: purgeAck() });
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find(`[data-testid="purge-${SHORT}"]`).trigger('click');
    await dialogInput(wrapper).setValue('nope');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).not.toHaveBeenCalled();
    expect(showMock).not.toHaveBeenCalled();
  });

  it('surfaces a 4xx in the dialog and stays open on failure', async () => {
    routeGet();
    mockApi.post.mockRejectedValue(axiosError(422, { error: 'Message queue is not connected' }));
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find(`[data-testid="purge-${SHORT}"]`).trigger('click');
    await dialogInput(wrapper).setValue(SHORT);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toContain('Message queue is not connected');
    expect(showMock).not.toHaveBeenCalled();
    expect(dialogInput(wrapper).exists()).toBe(true);
  });
});
