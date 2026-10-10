// src/tests/apps/admin/AdminJobs.spec.ts

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

// Render the HeadlessUI dialog markup synchronously.
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

import AdminConfirmDialog from '@/apps/admin/components/kit/AdminConfirmDialog.vue';
import AdminJobs from '@/apps/admin/views/AdminJobs.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

/** Pinned wall clock (Unix seconds). Every relative age is measured from it. */
const NOW = 1_700_000_000;

const JOBS_URL = '/api/colonel/jobs';
const DLQ_URL = '/api/colonel/queues/dlq';
const CHORES_URL = '/api/colonel/chores';
/** The short queue name: the URL segment AND the X-OTS-Confirm token. */
const QUEUE_SHORT = 'billing.event';
const PEEK_URL = `${DLQ_URL}/${QUEUE_SHORT}`;
const MESSAGE_URL = `${PEEK_URL}/messages/m1`;

const HOUSEKEEPING_ID = 'housekeeping.organization.standardize_owner_id';
const ENTITLEMENT_ID = 'entitlement_materialize';

// ---- Wire-shaped fixtures ---------------------------------------------------

function jobsPayload(schedulerAlive = true) {
  return {
    shrimp: '',
    record: {
      scheduler: {
        alive: schedulerAlive,
        started_at: NOW - 7200,
        heartbeat_at: NOW - 30,
        host: 'scheduler-1',
        pid: 4242,
        job_count: 2,
      },
    },
    details: {
      jobs: [
        {
          job_id: 'heartbeat',
          job_class: 'Onetime::Jobs::Scheduled::HeartbeatJob',
          group: 'scheduled',
          state: 'scheduled',
          schedule_kind: 'every',
          schedule_expression: '5m',
          next_time: NOW + 3600,
          registered_at: NOW - 7200,
          last_status: 'success',
          last_started_at: NOW - 300,
          last_finished_at: NOW - 299,
          last_duration_ms: 42,
          last_error: null,
          run_count: 12,
          error_count: 0,
        },
        {
          job_id: 'entitlement_materialize',
          job_class: 'Onetime::Jobs::Scheduled::Maintenance::EntitlementMaterializeJob',
          group: 'maintenance',
          state: 'not_scheduled',
          schedule_kind: null,
          schedule_expression: null,
          next_time: null,
          registered_at: null,
          last_status: 'error',
          last_started_at: NOW - 86_400,
          last_finished_at: NOW - 86_390,
          last_duration_ms: 10_250,
          last_error: 'aborted: catalog pull failed',
          run_count: 5,
          error_count: 2,
        },
      ],
      pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
    },
  };
}

function dlqPayload(connected = true) {
  return {
    shrimp: '',
    record: {},
    details: {
      dlqs: [
        { queue: 'dlq.billing.event', messages: 2, consumers: 0 },
        { queue: 'dlq.email.message', messages: 0, error: 'not declared' },
      ],
      pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
      connected,
    },
  };
}

function peekPayload() {
  return {
    shrimp: '',
    record: { queue: 'dlq.billing.event', total_messages: 2, showing: 2 },
    details: {
      messages: [
        {
          delivery_tag: 1,
          message_id: 'm1',
          timestamp: NOW - 60,
          age: '1m ago',
          original_queue: 'billing.event.process',
          death_reason: 'rejected',
          death_count: 2,
          error: 'Stripe::APIError: boom',
          content_type: 'application/json',
          payload_preview: '{"event":"invoice.paid"}',
        },
        {
          delivery_tag: 2,
          message_id: null,
          timestamp: null,
          age: 'unknown',
          original_queue: null,
          death_reason: null,
          death_count: null,
          error: null,
          content_type: null,
          payload_preview: 'raw',
        },
      ],
    },
  };
}

function inspectHit() {
  return {
    shrimp: '',
    record: {
      queue: 'dlq.billing.event',
      message_id: 'm1',
      found: true,
      scanned: 1,
      truncated: false,
    },
    details: {
      message: {
        delivery_tag: 1,
        message_id: 'm1',
        timestamp: '2023-11-14T22:13:20Z',
        content_type: 'application/json',
        headers: {},
        death_info: {
          original_queue: 'billing.event.process',
          original_exchange: '',
          reason: 'rejected',
          count: 2,
          time: '2023-11-14T22:13:21Z',
          routing_keys: ['billing.event.process'],
        },
        payload: { event: 'invoice.paid' },
      },
    },
  };
}

/** A miss on a valid queue: HTTP 200, not 404 (#4343 delta). */
function inspectMiss() {
  return {
    shrimp: '',
    record: {
      queue: 'dlq.billing.event',
      message_id: 'm1',
      found: false,
      outcome: 'not_visible',
      scanned: 500,
      truncated: true,
    },
    details: { message: null },
  };
}

function replayAck(found: boolean) {
  return {
    shrimp: '',
    record: {
      queue: 'dlq.billing.event',
      message_id: 'm1',
      found,
      outcome: found ? null : 'not_visible',
      scanned: found ? 1 : 500,
      truncated: !found,
      replayed: found ? 1 : 0,
      failed: 0,
      would_replay: 0,
      dry_run: false,
    },
    details: { message: found ? 'Replayed message' : 'Message not visible', errors: [] },
  };
}

function discardAck() {
  return {
    shrimp: '',
    record: {
      queue: 'dlq.billing.event',
      message_id: 'm1',
      found: true,
      scanned: 1,
      truncated: false,
      discarded: true,
      original_queue: 'billing.event.process',
      dry_run: false,
    },
    details: { message: 'Discarded message' },
  };
}

function chore(overrides: Record<string, unknown> = {}) {
  return {
    id: HOUSEKEEPING_ID,
    kind: 'housekeeping',
    model: 'Onetime::Organization',
    chores: ['standardize_owner_id'],
    supports_dry_run: false,
    cli: 'bin/ots housekeeping run Onetime::Organization',
    last_status: 'never',
    last_started_at: null,
    last_finished_at: null,
    last_duration_ms: null,
    last_error: null,
    run_count: 0,
    ...overrides,
  };
}

function choresPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      chores: [
        chore(),
        chore({
          id: ENTITLEMENT_ID,
          kind: 'billing',
          chores: [],
          supports_dry_run: true,
          cli: 'bin/ots billing plans materialize --all --include-memberships --run',
          last_status: 'success',
          last_started_at: NOW - 600,
          last_finished_at: NOW - 590,
          last_duration_ms: 9800,
          run_count: 3,
        }),
      ],
      pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
    },
  };
}

function choreRunAck(record: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: {
      chore: HOUSEKEEPING_ID,
      kind: 'housekeeping',
      status: 'success',
      dry_run: false,
      limit: 250,
      capped: false,
      budget_exhausted: false,
      duration_ms: 812,
      ...record,
    },
    details: {
      report: { model: 'Onetime::Organization', scanned: 180 },
      cli: 'bin/ots housekeeping run Onetime::Organization',
    },
  };
}

// ---- Harness ------------------------------------------------------------------

type GetRoutes = Record<string, () => unknown>;

/** Route GETs by URL; anything unrouted rejects so a stray request is loud. */
function routeGets(overrides: GetRoutes = {}): void {
  const routes: GetRoutes = {
    [JOBS_URL]: () => jobsPayload(),
    [DLQ_URL]: () => dlqPayload(),
    [CHORES_URL]: () => choresPayload(),
    [PEEK_URL]: () => peekPayload(),
    [MESSAGE_URL]: () => inspectHit(),
    ...overrides,
  };
  mockApi.get.mockImplementation((url: string) => {
    const route = routes[url];
    if (!route) return Promise.reject(new Error(`unrouted GET ${url}`));
    try {
      return Promise.resolve({ data: route() });
    } catch (err) {
      return Promise.reject(err);
    }
  });
}

const getCount = (url: string) => mockApi.get.mock.calls.filter((c) => c[0] === url).length;
const byTestId = (w: VueWrapper, id: string) => w.find(`[data-testid="${id}"]`);
const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogReason = (w: VueWrapper) => w.find('[data-testid="admin-confirm-reason"]');
/** The one AdminConfirmDialog currently open (both sections own one). */
const openDialog = (w: VueWrapper) =>
  w.findAllComponents(AdminConfirmDialog).find((d) => d.props('open'));

const relative = (value: number, unit: Intl.RelativeTimeFormatUnit) =>
  new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' }).format(value, unit);

async function mountView(): Promise<VueWrapper> {
  const pinia = createPinia();
  setActivePinia(pinia);
  const wrapper = mount(AdminJobs, { global: { plugins: [pinia, i18n] } });
  await flushPromises();
  return wrapper;
}

async function openPeek(w: VueWrapper): Promise<void> {
  await byTestId(w, 'dlq-peek-dlq.billing.event').trigger('click');
  await flushPromises();
}

/** Rendered view under test; unmounted after each example. */
let wrapper: VueWrapper | undefined;

/** Shared per-example setup: fresh mocks and a pinned wall clock. */
function useHarness(): void {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date(NOW * 1000));
  });

  afterEach(() => {
    vi.runOnlyPendingTimers();
    vi.useRealTimers();
    wrapper?.unmount();
    wrapper = undefined;
  });
}

describe('AdminJobs (#4343 — scheduler, DLQ message ops, chores)', () => {
  useHarness();

  it('issues the three independent GETs on mount and renders the three sections', async () => {
    routeGets();
    wrapper = await mountView();

    expect(mockApi.get).toHaveBeenCalledWith(JOBS_URL, { params: { page: 1, per_page: 50 } });
    expect(mockApi.get).toHaveBeenCalledWith(DLQ_URL, { params: { page: 1, per_page: 50 } });
    expect(mockApi.get).toHaveBeenCalledWith(CHORES_URL, undefined);
    expect(byTestId(wrapper, 'jobs-scheduler').exists()).toBe(true);
    expect(byTestId(wrapper, 'jobs-dlq').exists()).toBe(true);
    expect(byTestId(wrapper, 'jobs-chores').exists()).toBe(true);
    expect(wrapper.find('h2').text()).toBe('web.admin.jobs.title');
  });
});

// ---- Scheduler --------------------------------------------------------------

describe('AdminJobs — scheduler', () => {
  useHarness();

  it('renders a row per job with status, state and the last error', async () => {
    routeGets();
    wrapper = await mountView();

    expect(wrapper.findAll('[data-testid="jobs-table"] tbody tr')).toHaveLength(2);
    expect(byTestId(wrapper, 'job-status-heartbeat').text()).toBe('web.admin.jobs.status.success');
    expect(byTestId(wrapper, 'job-state-entitlement_materialize').text()).toBe(
      'web.admin.jobs.scheduler.state.not_scheduled'
    );
    const error = byTestId(wrapper, 'job-error-entitlement_materialize');
    expect(error.text()).toBe('aborted: catalog pull failed');
    expect(error.attributes('title')).toBe('aborted: catalog pull failed');
    expect(byTestId(wrapper, 'jobs-scheduler-process').text()).toContain('scheduler-1 · 4242');
  });

  it('measures next-due and heartbeat ages from the fetch time, not render time', async () => {
    routeGets();
    wrapper = await mountView();

    expect(byTestId(wrapper, 'job-next-heartbeat').text()).toBe(relative(1, 'hour'));
    expect(byTestId(wrapper, 'job-next-heartbeat').attributes('title')).toBe(
      new Date((NOW + 3600) * 1000).toISOString()
    );
    expect(byTestId(wrapper, 'job-next-entitlement_materialize').text()).toBe('—');
    expect(byTestId(wrapper, 'jobs-scheduler-heartbeat').text()).toContain(relative(-30, 'second'));

    // Time passing on screen does not move the ages until the next fetch.
    vi.setSystemTime(new Date((NOW + 1800) * 1000));
    await wrapper.vm.$nextTick();
    expect(byTestId(wrapper, 'job-next-heartbeat').text()).toBe(relative(1, 'hour'));
  });

  it('warns that times may be stale when the scheduler is not alive', async () => {
    routeGets({ [JOBS_URL]: () => jobsPayload(false) });
    wrapper = await mountView();

    expect(byTestId(wrapper, 'jobs-scheduler-status').text()).toContain(
      'web.admin.jobs.scheduler.notSeen'
    );
    expect(byTestId(wrapper, 'jobs-scheduler-not-seen').exists()).toBe(true);
  });

  it('shows its own error + retry without blanking the other sections', async () => {
    routeGets({
      [JOBS_URL]: () => {
        throw axiosError(500, { error: 'boom' });
      },
    });
    wrapper = await mountView();

    expect(byTestId(wrapper, 'jobs-scheduler-error').exists()).toBe(true);
    expect(wrapper.findAll('[data-testid="dlq-table"] tbody tr')).toHaveLength(2);
    expect(wrapper.findAll('[data-testid="chores-table"] tbody tr')).toHaveLength(2);

    routeGets();
    await byTestId(wrapper, 'jobs-scheduler-error').find('button').trigger('click');
    await flushPromises();
    expect(byTestId(wrapper, 'jobs-scheduler-error').exists()).toBe(false);
    expect(wrapper.findAll('[data-testid="jobs-table"] tbody tr')).toHaveLength(2);
  });
});

// ---- Dead-letter queues -------------------------------------------------------

describe('AdminJobs — dead-letter queues', () => {
  useHarness();

  it('says the broker is disconnected rather than showing depths as empty', async () => {
    routeGets({ [DLQ_URL]: () => dlqPayload(false) });
    wrapper = await mountView();

    expect(byTestId(wrapper, 'jobs-dlq-disconnected').exists()).toBe(true);
  });

  it('peeks a queue by its short name and lists its messages in the drawer', async () => {
    routeGets();
    wrapper = await mountView();
    await openPeek(wrapper);

    expect(mockApi.get).toHaveBeenCalledWith(PEEK_URL, undefined);
    expect(byTestId(wrapper, 'dlq-drawer-content').exists()).toBe(true);
    expect(byTestId(wrapper, 'dlq-message-m1').text()).toContain('billing.event.process');
    // A message without an id cannot be addressed: no row actions, a CLI hint.
    const anonymous = byTestId(wrapper, 'dlq-message-1');
    expect(anonymous.find('button').exists()).toBe(false);
    expect(anonymous.text()).toContain('web.admin.jobs.dlq.drawer.noMessageId');
  });

  it('inspects one message in place and renders its full detail', async () => {
    routeGets();
    wrapper = await mountView();
    await openPeek(wrapper);

    await byTestId(wrapper, 'dlq-inspect-m1').trigger('click');
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(MESSAGE_URL, undefined);
    expect(byTestId(wrapper, 'dlq-inspect-json').exists()).toBe(true);
    expect(byTestId(wrapper, 'dlq-inspect-not-visible').exists()).toBe(false);
  });

  it('shows a not-visible miss (HTTP 200) plainly, with the truncated scan', async () => {
    routeGets({ [MESSAGE_URL]: () => inspectMiss() });
    wrapper = await mountView();
    await openPeek(wrapper);

    await byTestId(wrapper, 'dlq-inspect-m1').trigger('click');
    await flushPromises();

    expect(byTestId(wrapper, 'dlq-inspect-json').exists()).toBe(false);
    expect(byTestId(wrapper, 'dlq-inspect-not-visible').text()).toBe(
      'web.admin.jobs.dlq.notVisible'
    );
    expect(byTestId(wrapper, 'dlq-inspect-truncated').text()).toBe('web.admin.jobs.dlq.truncated');
  });

  it('gates discard behind a DANGER dialog whose token is the short queue name', async () => {
    routeGets();
    wrapper = await mountView();
    await openPeek(wrapper);

    await byTestId(wrapper, 'dlq-discard-m1').trigger('click');
    await flushPromises();

    const dialog = openDialog(wrapper);
    expect(dialog?.props('variant')).toBe('danger');
    expect(dialog?.props('confirmToken')).toBe(QUEUE_SHORT);
    expect(dialog?.props('requestReason')).toBe(true);
  });

  it('discards with X-OTS-Confirm + reason, notifies, re-peeks and refreshes the list', async () => {
    routeGets();
    mockApi.post.mockResolvedValue({ data: discardAck() });
    wrapper = await mountView();
    await openPeek(wrapper);
    const peeks = getCount(PEEK_URL);
    const lists = getCount(DLQ_URL);

    await byTestId(wrapper, 'dlq-discard-m1').trigger('click');
    await dialogInput(wrapper).setValue(QUEUE_SHORT);
    await dialogReason(wrapper).setValue('poison message');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      `${MESSAGE_URL}/discard`,
      { dry_run: false, reason: 'poison message' },
      { headers: { 'X-OTS-Confirm': encodeURIComponent(QUEUE_SHORT) } }
    );
    expect(showMock).toHaveBeenCalledWith('web.admin.jobs.dlq.discard.success', 'success');
    expect(openDialog(wrapper)).toBeUndefined();
    expect(getCount(PEEK_URL)).toBe(peeks + 1);
    expect(getCount(DLQ_URL)).toBe(lists + 1);
  });

  it('does not post when the typed token does not match', async () => {
    routeGets();
    wrapper = await mountView();
    await openPeek(wrapper);

    await byTestId(wrapper, 'dlq-discard-m1').trigger('click');
    await dialogInput(wrapper).setValue('dlq.billing.event'); // full name is not the token
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).not.toHaveBeenCalled();
  });

  it('replays through a DEFAULT-variant dialog and reports success', async () => {
    routeGets();
    mockApi.post.mockResolvedValue({ data: replayAck(true) });
    wrapper = await mountView();
    await openPeek(wrapper);

    await byTestId(wrapper, 'dlq-replay-m1').trigger('click');
    await flushPromises();
    expect(openDialog(wrapper)?.props('variant')).toBe('default');

    await dialogInput(wrapper).setValue(QUEUE_SHORT);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    // No reason typed: the body carries no `reason` key at all (#4338).
    expect(mockApi.post).toHaveBeenCalledWith(
      `${MESSAGE_URL}/replay`,
      { dry_run: false },
      { headers: { 'X-OTS-Confirm': encodeURIComponent(QUEUE_SHORT) } }
    );
    expect(showMock).toHaveBeenCalledWith('web.admin.jobs.dlq.replay.success', 'success');
  });

  it('reports a not-visible replay as a warning, never as success', async () => {
    routeGets();
    mockApi.post.mockResolvedValue({ data: replayAck(false) });
    wrapper = await mountView();
    await openPeek(wrapper);

    await byTestId(wrapper, 'dlq-replay-m1').trigger('click');
    await dialogInput(wrapper).setValue(QUEUE_SHORT);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(showMock).toHaveBeenCalledWith('web.admin.jobs.dlq.result.notVisible', 'warning');
    expect(showMock).not.toHaveBeenCalledWith('web.admin.jobs.dlq.replay.success', 'success');
    expect(byTestId(wrapper, 'dlq-last-action-not-visible').exists()).toBe(true);
    expect(byTestId(wrapper, 'dlq-last-action-truncated').exists()).toBe(true);
  });

  it('keeps the dialog open with the server message on a 4xx', async () => {
    routeGets();
    mockApi.post.mockRejectedValue(axiosError(404, { error: 'Unknown dead-letter queue' }));
    wrapper = await mountView();
    await openPeek(wrapper);

    await byTestId(wrapper, 'dlq-replay-m1').trigger('click');
    await dialogInput(wrapper).setValue(QUEUE_SHORT);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(openDialog(wrapper)?.props('error')).toContain('Unknown dead-letter queue');
    expect(showMock).not.toHaveBeenCalled();
  });
});

// ---- Chores -------------------------------------------------------------------

describe('AdminJobs — chores', () => {
  useHarness();

  it('shows the equivalent CLI command per chore', async () => {
    routeGets();
    wrapper = await mountView();

    expect(byTestId(wrapper, `chore-cli-${HOUSEKEEPING_ID}`).text()).toBe(
      'bin/ots housekeeping run Onetime::Organization'
    );
    expect(byTestId(wrapper, `chore-cli-${ENTITLEMENT_ID}`).text()).toContain(
      'billing plans materialize'
    );
  });

  it('offers Preview only where the server supports a dry run', async () => {
    routeGets();
    wrapper = await mountView();

    expect(byTestId(wrapper, `chore-preview-${ENTITLEMENT_ID}`).exists()).toBe(true);
    expect(byTestId(wrapper, `chore-preview-${HOUSEKEEPING_ID}`).exists()).toBe(false);
  });

  it('previews with dry_run and no confirmation, and shows the report inline', async () => {
    routeGets();
    mockApi.post.mockResolvedValue({
      data: choreRunAck({
        chore: ENTITLEMENT_ID,
        kind: 'billing',
        status: 'dry_run',
        dry_run: true,
        limit: 100,
        duration_ms: null,
      }),
    });
    wrapper = await mountView();

    await byTestId(wrapper, `chore-preview-${ENTITLEMENT_ID}`).trigger('click');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(`${CHORES_URL}/${ENTITLEMENT_ID}/run`, {
      dry_run: true,
      limit: 100,
    });
    expect(openDialog(wrapper)).toBeUndefined();
    expect(byTestId(wrapper, 'chores-result-preview').exists()).toBe(true);
    expect(byTestId(wrapper, 'chores-result-report').exists()).toBe(true);
  });

  it('runs behind a typed chore-id gate with a limit and reason', async () => {
    routeGets();
    mockApi.post.mockResolvedValue({ data: choreRunAck() });
    wrapper = await mountView();
    const lists = getCount(CHORES_URL);

    await byTestId(wrapper, `chore-run-${HOUSEKEEPING_ID}`).trigger('click');
    await flushPromises();
    const dialog = openDialog(wrapper);
    expect(dialog?.props('confirmToken')).toBe(HOUSEKEEPING_ID);
    expect(dialog?.props('variant')).toBe('default');

    await byTestId(wrapper, 'chore-run-limit').setValue('250');
    await dialogInput(wrapper).setValue(HOUSEKEEPING_ID);
    await dialogReason(wrapper).setValue('owner ids drifted');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      `${CHORES_URL}/${HOUSEKEEPING_ID}/run`,
      { dry_run: false, limit: 250, reason: 'owner ids drifted' },
      { headers: { 'X-OTS-Confirm': encodeURIComponent(HOUSEKEEPING_ID) } }
    );
    expect(showMock).toHaveBeenCalledWith('web.admin.jobs.chores.run.success', 'success');
    expect(byTestId(wrapper, 'chores-result-cli').text()).toBe(
      'bin/ots housekeeping run Onetime::Organization'
    );
    expect(getCount(CHORES_URL)).toBe(lists + 1);
  });

  it('surfaces capped and budget_exhausted runs as partial, never as plain success', async () => {
    routeGets();
    mockApi.post.mockResolvedValue({
      data: choreRunAck({ capped: true, budget_exhausted: true }),
    });
    wrapper = await mountView();

    await byTestId(wrapper, `chore-run-${HOUSEKEEPING_ID}`).trigger('click');
    await dialogInput(wrapper).setValue(HOUSEKEEPING_ID);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(showMock).toHaveBeenCalledWith('web.admin.jobs.chores.run.partial', 'warning');
    expect(byTestId(wrapper, 'chores-result-capped').exists()).toBe(true);
    expect(byTestId(wrapper, 'chores-result-budget').exists()).toBe(true);
  });

  it('refuses to post an out-of-range limit', async () => {
    routeGets();
    wrapper = await mountView();

    await byTestId(wrapper, `chore-run-${HOUSEKEEPING_ID}`).trigger('click');
    await byTestId(wrapper, 'chore-run-limit').setValue('0');
    await dialogInput(wrapper).setValue(HOUSEKEEPING_ID);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).not.toHaveBeenCalled();
    expect(byTestId(wrapper, 'chore-run-limit').attributes('aria-invalid')).toBe('true');
  });
});
