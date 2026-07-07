// src/tests/apps/admin/AdminBanner.spec.ts

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

// Render the HeadlessUI dialog markup synchronously (mirrors AdminBannedIps.spec).
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

import AdminBanner from '@/apps/admin/views/AdminBanner.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const BANNER_URL = '/api/colonel/banner';
const CONTENT = '<a href="/status">Scheduled maintenance</a>';

function bannerPayload(overrides: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: { content: CONTENT, ttl: null, active: true, ...overrides },
    details: { key: 'global_banner', database: 0 },
  };
}

function emptyPayload() {
  return {
    shrimp: '',
    record: { content: null, ttl: null, active: false },
    details: { key: 'global_banner', database: 0 },
  };
}

function setAck() {
  return {
    shrimp: '',
    record: { content: 'New notice', ttl: null, active: true },
    details: { message: 'Broadcast banner published' },
  };
}

function clearAck() {
  return {
    shrimp: '',
    record: { cleared: true, active: false },
    details: { message: 'Broadcast banner cleared' },
  };
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminBanner, { global: { plugins: [pinia, i18n] } });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');
const bannerGetCount = () => mockApi.get.mock.calls.filter((c) => c[0] === BANNER_URL).length;

describe('AdminBanner (settings screen — ticket #41)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  // ---- Read -----------------------------------------------------------------

  it('fetches the current banner on mount and renders its stored content', async () => {
    mockApi.get.mockResolvedValue({ data: bannerPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    // Single-GET read — no pagination params.
    expect(mockApi.get).toHaveBeenCalledWith(BANNER_URL, undefined);
    const active = wrapper.find('[data-testid="banner-active"]');
    expect(active.exists()).toBe(true);
    // Content is rendered as escaped text (the raw HTML string is visible).
    expect(wrapper.find('[data-testid="banner-content"]').text()).toContain('/status');
    // A clear action is offered for a live banner.
    expect(wrapper.find('[data-testid="banner-clear"]').exists()).toBe(true);
  });

  it('renders the empty state when no banner is set', async () => {
    mockApi.get.mockResolvedValue({ data: emptyPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="banner-empty"]').exists()).toBe(true);
    // No live banner ⇒ no clear button.
    expect(wrapper.find('[data-testid="banner-clear"]').exists()).toBe(false);
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    const banner = wrapper.find('[data-testid="banner-error"]');
    expect(banner.exists()).toBe(true);

    mockApi.get.mockResolvedValueOnce({ data: bannerPayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="banner-error"]').exists()).toBe(false);
  });

  // ---- Publish (one-click confirm) -----------------------------------------

  describe('publish', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: emptyPayload() });
      wrapper = mountView(pinia);
      await flushPromises();
    });

    it('publish is disabled until a message is entered', async () => {
      const publish = wrapper.find('[data-testid="banner-publish"]');
      expect(publish.attributes('disabled')).toBeDefined();
      await wrapper.find('[data-testid="banner-content-input"]').setValue('Heads up');
      expect(publish.attributes('disabled')).toBeUndefined();
    });

    it('opens a one-click confirm (no typed gate) and POSTs {content, ttl}', async () => {
      mockApi.post.mockResolvedValue({ data: setAck() });
      const before = bannerGetCount();

      await wrapper.find('[data-testid="banner-content-input"]').setValue('Heads up');
      await wrapper.find('[data-testid="banner-ttl-input"]').setValue('3600');
      await wrapper.find('[data-testid="banner-publish"]').trigger('click');
      await flushPromises();

      // Simple confirm: no typed-token input, submit immediately enabled.
      expect(dialogInput(wrapper).exists()).toBe(false);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(BANNER_URL, {
        content: 'Heads up',
        ttl: 3600,
      });
      expect(showMock).toHaveBeenCalledWith('web.admin.banner.set.success', 'success');
      expect(bannerGetCount()).toBe(before + 1);
    });

    it('omits ttl when the field is blank', async () => {
      mockApi.post.mockResolvedValue({ data: setAck() });
      await wrapper.find('[data-testid="banner-content-input"]').setValue('Persistent notice');
      await wrapper.find('[data-testid="banner-publish"]').trigger('click');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(BANNER_URL, {
        content: 'Persistent notice',
        ttl: undefined,
      });
    });

    it('surfaces a 4xx in the dialog and does not refresh on failure', async () => {
      mockApi.post.mockRejectedValue(axiosError(422, { error: 'Banner content is required' }));
      const before = bannerGetCount();

      await wrapper.find('[data-testid="banner-content-input"]').setValue('x');
      await wrapper.find('[data-testid="banner-publish"]').trigger('click');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[role="alert"]').text()).toContain('Banner content is required');
      expect(showMock).not.toHaveBeenCalled();
      expect(bannerGetCount()).toBe(before);
    });
  });

  // ---- Clear (typed-confirmation) ------------------------------------------

  describe('clear', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: bannerPayload() });
      wrapper = mountView(pinia);
      await flushPromises();
    });

    it('gates the destructive clear behind retyping the confirmation word', async () => {
      await wrapper.find('[data-testid="banner-clear"]').trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue('nope');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue('clear');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('DELETEs the banner, notifies and refreshes on confirm', async () => {
      mockApi.delete.mockResolvedValue({ data: clearAck() });
      const before = bannerGetCount();

      await wrapper.find('[data-testid="banner-clear"]').trigger('click');
      await dialogInput(wrapper).setValue('clear');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(BANNER_URL);
      expect(showMock).toHaveBeenCalledWith('web.admin.banner.clear.success', 'success');
      expect(dialogInput(wrapper).exists()).toBe(false);
      expect(bannerGetCount()).toBe(before + 1);
    });

    it('does NOT DELETE when submitted without the matching word', async () => {
      mockApi.delete.mockResolvedValue({ data: clearAck() });
      await wrapper.find('[data-testid="banner-clear"]').trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });
  });
});
