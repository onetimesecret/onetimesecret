// src/tests/apps/admin/AdminEmailTools.spec.ts

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

// Render the HeadlessUI dialog markup synchronously (mirrors AdminBanner.spec).
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

import AdminEmailTools from '@/apps/admin/views/AdminEmailTools.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const CONFIG_URL = '/api/colonel/email/config';
const TEMPLATES_URL = '/api/colonel/email/templates';
const TEST_URL = '/api/colonel/email/test';
const PROVIDER_STATUS_URL = '/api/colonel/email/deliverability/provider-status';

function configPayload(provider = 'smtp') {
  return {
    shrimp: '',
    record: {},
    details: {
      provider,
      auto_detected: true,
      from_address: 'secure@onetime.dev',
      from_name: 'Onetime Secret',
      provider_config: {
        host: 'smtp.example.com',
        port: 587,
        domain: null,
        tls: true,
        region: null,
        has_credentials: true,
      },
      sender_provider: provider,
      sender_differs: false,
    },
  };
}

function templatesPayload() {
  return {
    shrimp: '',
    record: {
      templates: [
        { name: 'secret_link', class_name: 'SecretLink', formats: ['text', 'html'] },
        { name: 'welcome', class_name: 'Welcome', formats: ['text'] },
      ],
    },
    details: { count: 2 },
  };
}

function previewPayload(format: 'text' | 'html' = 'text', body = 'Hello preview body') {
  return {
    shrimp: '',
    record: { template: 'secret_link', locale: 'en', format },
    details: { body },
  };
}

function testPayload(status: 'dry_run' | 'sent') {
  return {
    shrimp: '',
    record: { to: 'ops@example.com', status, sent: status !== 'dry_run' },
    details: {
      provider: 'logger',
      host: 'vm',
      from: 'secure@onetime.dev',
      subject: '[Secure Links] Email delivery test',
      text_body: 'This is a test email.',
      timestamp: '2026-07-07T00:00:00Z',
    },
  };
}

/**
 * Provider-status (Track B) payload. `provider='smtp'` is the non-live
 * transport shape (capability=false); pass a live provider + block to exercise
 * the OK path, or `available=false` to exercise the degraded/retry path.
 */
function providerStatusPayload(
  overrides: Partial<{
    provider: string;
    capability: boolean;
    available: boolean;
    error: string | null;
    ses: unknown;
    lettermint: unknown;
  }> = {}
) {
  return {
    shrimp: '',
    record: {},
    details: {
      provider: 'smtp',
      capability: false,
      available: false,
      error: null,
      ses: null,
      lettermint: null,
      ...overrides,
    },
  };
}

function sesStatusPayload() {
  return providerStatusPayload({
    provider: 'ses',
    capability: true,
    available: true,
    ses: {
      enforcement_status: 'HEALTHY',
      production_access_enabled: true,
      sending_enabled: true,
      max_24_hour_send: 50000,
      sent_last_24_hours: 1234,
      max_send_rate: 14,
      rate_bounce: null,
      rate_complaint: null,
      rate_note: 'SESv2 exposes no numeric bounce/complaint rate.',
    },
  });
}

/** Default happy-path GET router: mailer config + templates + provider status. */
function primeMountGets(provider = 'smtp', providerStatus: unknown = providerStatusPayload()) {
  mockApi.get.mockImplementation((url: string) => {
    if (url === CONFIG_URL) return Promise.resolve({ data: configPayload(provider) });
    if (url === TEMPLATES_URL) return Promise.resolve({ data: templatesPayload() });
    if (url === PROVIDER_STATUS_URL) return Promise.resolve({ data: providerStatus });
    return Promise.reject(new Error(`unexpected GET ${url}`));
  });
}

// The deliverability section owns its own fetches and has a dedicated spec
// (EmailDeliverabilitySection.spec.ts); stub it here so this spec keeps
// asserting exactly what the VIEW requests on mount.
const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminEmailTools, {
    global: { plugins: [pinia, i18n], stubs: { EmailDeliverabilitySection: true } },
  });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

describe('AdminEmailTools (email tools — ticket #44)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  // ---- Reference lists ------------------------------------------------------

  it('loads the mailer config + template picker on mount and nothing else', async () => {
    primeMountGets();
    wrapper = mountView(pinia);
    await flushPromises();

    // useResourceFetch issues the config GET as get(url, undefined).
    expect(mockApi.get).toHaveBeenCalledWith(CONFIG_URL, undefined);
    expect(mockApi.get).toHaveBeenCalledWith(TEMPLATES_URL);
    // Track B: the provider-status card reads the ACTIVE transport on mount
    // (no query params → get(url, undefined)).
    expect(mockApi.get).toHaveBeenCalledWith(PROVIDER_STATUS_URL, undefined);
    // The rate-limit half was removed by design review: the screen must not
    // touch the (still live) ratelimit endpoints. On mount it reads exactly the
    // read-only mailer config (ITEM 1), the template picker, and the Track-B
    // provider-status card.
    expect(mockApi.get).toHaveBeenCalledTimes(3);
    const options = wrapper.find('[data-testid="preview-template-select"]').findAll('option');
    expect(options.map((o) => o.text())).toEqual(['secret_link', 'welcome']);
  });

  it('renders no rate-limit section (endpoints stay CLI/API-only)', async () => {
    primeMountGets();
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="ratelimit-section"]').exists()).toBe(false);
  });

  it('mounts the deliverability section (fetches covered by its own spec)', async () => {
    primeMountGets();
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.findComponent({ name: 'EmailDeliverabilitySection' }).exists()).toBe(true);
  });

  // ---- Provider status (Track B) --------------------------------------------

  it('renders the SES reputation tier + quota on the OK path', async () => {
    primeMountGets('ses', sesStatusPayload());
    wrapper = mountView(pinia);
    await flushPromises();

    const section = wrapper.find('[data-testid="provider-status-section"]');
    expect(section.exists()).toBe(true);
    expect(wrapper.find('[data-testid="provider-status-ses"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="provider-status-tier"]').text()).toContain(
      'web.admin.emailtools.providerStatus.tier.healthy'
    );
    expect(wrapper.find('[data-testid="provider-status-max24h"]').text()).toContain('50000');
    // SESv2 has no numeric rate → the degraded-rate note renders (NOT an error).
    expect(wrapper.find('[data-testid="provider-status-rate-note"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="provider-status-error"]').exists()).toBe(false);
  });

  it('renders the not-supported empty-state for a non-live transport (capability=false)', async () => {
    primeMountGets('smtp'); // default providerStatusPayload() is capability=false
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="provider-status-unsupported"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="provider-status-error"]').exists()).toBe(false);
  });

  it('degrades a network failure to the retry alert without unmounting the section', async () => {
    primeMountGets();
    mockApi.get.mockImplementation((url: string) => {
      if (url === CONFIG_URL) return Promise.resolve({ data: configPayload('smtp') });
      if (url === TEMPLATES_URL) return Promise.resolve({ data: templatesPayload() });
      if (url === PROVIDER_STATUS_URL) return Promise.reject(axiosError(500, { error: 'boom' }));
      return Promise.reject(new Error(`unexpected GET ${url}`));
    });
    wrapper = mountView(pinia);
    await flushPromises();

    // The whole page (and section) stays mounted; the card shows a retry alert.
    expect(wrapper.find('[data-testid="provider-status-section"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="provider-status-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="preview-section"]').exists()).toBe(true);
  });

  it('degrades a 200 available=false payload to the retry alert with the server note', async () => {
    primeMountGets(
      'ses',
      providerStatusPayload({
        provider: 'ses',
        capability: true,
        available: false,
        error: 'SES get_account timed out after 5s',
      })
    );
    wrapper = mountView(pinia);
    await flushPromises();

    const alert = wrapper.find('[data-testid="provider-status-error"]');
    expect(alert.exists()).toBe(true);
    expect(alert.text()).toContain('SES get_account timed out after 5s');
    expect(wrapper.find('[data-testid="provider-status-ses"]').exists()).toBe(false);
  });

  // ---- Section 1: preview ---------------------------------------------------

  it('renders a TEXT preview as escaped source (read-only, GET with params)', async () => {
    primeMountGets();
    wrapper = mountView(pinia);
    await flushPromises();

    mockApi.get.mockResolvedValueOnce({ data: previewPayload('text', 'RENDERED TEXT') });
    await wrapper.find('[data-testid="preview-run"]').trigger('click');
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(
      `${TEMPLATES_URL}/secret_link/preview`,
      { params: { format: 'text', locale: 'en' } }
    );
    expect(wrapper.find('[data-testid="preview-body"]').text()).toContain('RENDERED TEXT');
    // Text format never uses the iframe.
    expect(wrapper.find('[data-testid="preview-iframe"]').exists()).toBe(false);
  });

  it('renders an HTML preview in a sandboxed iframe (no v-html)', async () => {
    primeMountGets();
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="preview-format-select"]').setValue('html');
    mockApi.get.mockResolvedValueOnce({ data: previewPayload('html', '<h1>Hi</h1>') });
    await wrapper.find('[data-testid="preview-run"]').trigger('click');
    await flushPromises();

    const iframe = wrapper.find('[data-testid="preview-iframe"]');
    expect(iframe.exists()).toBe(true);
    expect(iframe.attributes('sandbox')).toBe('');
    expect(iframe.attributes('srcdoc')).toContain('<h1>Hi</h1>');
  });

  // ---- Section 2: test send -------------------------------------------------

  it('previews the diagnostic with dry_run:true (sends nothing)', async () => {
    primeMountGets();
    wrapper = mountView(pinia);
    await flushPromises();

    mockApi.post.mockResolvedValueOnce({ data: testPayload('dry_run') });
    await wrapper.find('[data-testid="test-to-input"]').setValue('ops@example.com');
    await wrapper.find('[data-testid="test-preview"]').trigger('click');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(TEST_URL, {
      to: 'ops@example.com',
      enqueue: false,
      dry_run: true,
    });
    expect(wrapper.find('[data-testid="test-diagnostic"]').exists()).toBe(true);
    expect(showMock).not.toHaveBeenCalled();
  });

  it('gates the real send behind a one-click confirm and POSTs dry_run:false', async () => {
    primeMountGets();
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="test-to-input"]').setValue('ops@example.com');
    await wrapper.find('[data-testid="test-send"]').trigger('click');
    await flushPromises();

    // One-click: no typed-token input, submit immediately enabled.
    expect(dialogInput(wrapper).exists()).toBe(false);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

    mockApi.post.mockResolvedValueOnce({ data: testPayload('sent') });
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(TEST_URL, {
      to: 'ops@example.com',
      enqueue: false,
      dry_run: false,
    });
    expect(showMock).toHaveBeenCalledWith('web.admin.emailtools.test.success', 'success');
  });

  it('surfaces a 4xx from the send in the dialog and does not notify', async () => {
    primeMountGets();
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="test-to-input"]').setValue('ops@example.com');
    await wrapper.find('[data-testid="test-send"]').trigger('click');
    mockApi.post.mockRejectedValueOnce(axiosError(422, { error: 'Delivery failed: boom' }));
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toContain('Delivery failed: boom');
    expect(showMock).not.toHaveBeenCalled();
  });
});
