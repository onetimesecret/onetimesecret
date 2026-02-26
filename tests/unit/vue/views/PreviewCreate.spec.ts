// tests/unit/vue/views/PreviewCreate.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { ref, nextTick, defineComponent } from 'vue';
import PreviewCreate from '@/views/PreviewCreate.vue';

// ── Mocks ──────────────────────────────────────────────────────────

vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog"><slot /></div>',
    props: ['as'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div><slot /></div>',
  },
  DialogTitle: {
    name: 'DialogTitle',
    template: '<h2><slot /></h2>',
  },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['show', 'appear', 'as'],
  },
  TransitionChild: {
    name: 'TransitionChild',
    template: '<div><slot /></div>',
  },
}));

const mockShowModal = ref(false);
const mockModalData = ref<Record<string, unknown> | null>(null);
const mockHandleSecretCreated = vi.fn();
const mockHandleCloseModal = vi.fn();

vi.mock('@/composables/useSecretLinkPopup', () => ({
  useSecretLinkPopup: () => ({
    showModal: mockShowModal,
    modalData: mockModalData,
    handleSecretCreated: mockHandleSecretCreated,
    handleCloseModal: mockHandleCloseModal,
  }),
}));

// ── Helpers ────────────────────────────────────────────────────────

function createI18nPlugin() {
  return createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        'web.LABELS.close': 'Close',
        'web.LABELS.secret_link': 'Secret Link',
        'web.LABELS.expires_in': 'Expires in {time}',
        'web.LABELS.passphrase_protected': 'Passphrase protected',
        'web.LABELS.view_details': 'View Details',
        'web.LABELS.show_details': 'Show details',
        'web.LABELS.hide_details': 'Hide details',
        'web.COMMON.share_link_securely': 'Share this link securely',
        'web.private.created_success': 'Secret link created',
        'web.STATUS.securing': 'Loading',
        'web.STATUS.created': 'Created',
        'web.STATUS.expires': 'Expires',
        'web.LABELS.timeline': 'Timeline',
      },
    },
  });
}

const SecretFormStub = defineComponent({
  name: 'SecretForm',
  props: ['withExpiry', 'onSecretCreated'],
  template: '<div class="secret-form-stub" />',
});

const CopyFirstModalStub = defineComponent({
  name: 'SecretLinkCopyFirstModal',
  props: ['show', 'shareUrl', 'naturalExpiration', 'hasPassphrase', 'metadataKey', 'secretShortkey'],
  emits: ['close'],
  template: '<div class="copy-first-modal" v-if="show" data-testid="copy-first-modal"><slot /></div>',
});

function createWrapper() {
  return mount(PreviewCreate, {
    global: {
      plugins: [createI18nPlugin()],
      stubs: {
        SecretForm: SecretFormStub,
        SecretLinkCopyFirstModal: CopyFirstModalStub,
        OIcon: { template: '<span />' },
        CopyButton: {
          name: 'CopyButton',
          template: '<button class="copy-btn" />',
          props: ['text'],
        },
        RouterLink: {
          template: '<a :href="to"><slot /></a>',
          props: ['to'],
        },
        Transition: {
          template: '<div><slot /></div>',
        },
        StatusBadge: { template: '<span />' },
      },
    },
  });
}

// ── Tests ──────────────────────────────────────────────────────────

describe('PreviewCreate', () => {
  beforeEach(() => {
    mockShowModal.value = false;
    mockModalData.value = null;
    mockHandleSecretCreated.mockClear();
    mockHandleCloseModal.mockClear();
  });

  describe('preview mode indicator', () => {
    it('renders the copy-first mode indicator badge', () => {
      const wrapper = createWrapper();
      expect(wrapper.text()).toContain('Preview mode');
      expect(wrapper.text()).toContain('copy-first');
    });
  });

  describe('modal rendering', () => {
    it('renders CopyFirstModal when modalData is set', async () => {
      mockModalData.value = {
        shareUrl: 'https://example.com/secret/abc123',
        naturalExpiration: '24 hours',
        hasPassphrase: false,
        metadataKey: 'testkey123',
        secretShortkey: 'abc123',
      };
      mockShowModal.value = true;

      const wrapper = createWrapper();
      await nextTick();

      const modal = wrapper.findComponent(CopyFirstModalStub);
      expect(modal.exists()).toBe(true);
    });

    it('does not render modal when modalData is null', () => {
      mockModalData.value = null;
      mockShowModal.value = false;

      const wrapper = createWrapper();
      expect(wrapper.find('[data-testid="copy-first-modal"]').exists()).toBe(false);
    });

    it('renders modal when modalData becomes available', async () => {
      const wrapper = createWrapper();
      expect(wrapper.find('[data-testid="copy-first-modal"]').exists()).toBe(false);

      mockModalData.value = {
        shareUrl: 'https://example.com/secret/abc123',
        naturalExpiration: '24 hours',
        hasPassphrase: false,
        metadataKey: 'testkey123',
        secretShortkey: 'abc123',
      };
      mockShowModal.value = true;
      await nextTick();

      expect(wrapper.findComponent(CopyFirstModalStub).exists()).toBe(true);
    });

    it('hides modal when showModal becomes false', async () => {
      mockModalData.value = {
        shareUrl: 'https://example.com/secret/abc123',
        naturalExpiration: '24 hours',
        hasPassphrase: false,
        metadataKey: 'testkey123',
        secretShortkey: 'abc123',
      };
      mockShowModal.value = true;

      const wrapper = createWrapper();
      await nextTick();

      const modal = wrapper.findComponent(CopyFirstModalStub);
      expect(modal.exists()).toBe(true);
      expect(modal.props('show')).toBe(true);

      mockShowModal.value = false;
      await nextTick();

      const modalAfter = wrapper.findComponent(CopyFirstModalStub);
      expect(modalAfter.exists()).toBe(true);
      expect(modalAfter.props('show')).toBe(false);
    });

    it('passes correct props to CopyFirstModal from modalData', async () => {
      mockModalData.value = {
        shareUrl: 'https://example.com/secret/xyz789',
        naturalExpiration: '48 hours',
        hasPassphrase: true,
        metadataKey: 'meta-xyz',
        secretShortkey: 'xyz789',
      };
      mockShowModal.value = true;

      const wrapper = createWrapper();
      await nextTick();

      const modal = wrapper.findComponent(CopyFirstModalStub);
      expect(modal.props('shareUrl')).toBe('https://example.com/secret/xyz789');
      expect(modal.props('naturalExpiration')).toBe('48 hours');
      expect(modal.props('hasPassphrase')).toBe(true);
      expect(modal.props('metadataKey')).toBe('meta-xyz');
      expect(modal.props('secretShortkey')).toBe('xyz789');
    });
  });

  describe('SecretForm wiring', () => {
    it('renders SecretForm component', () => {
      const wrapper = createWrapper();
      const form = wrapper.findComponent(SecretFormStub);
      expect(form.exists()).toBe(true);
    });

    it('passes handleSecretCreated callback to SecretForm', () => {
      const wrapper = createWrapper();
      const secretForm = wrapper.findComponent(SecretFormStub);
      expect(secretForm.props('onSecretCreated')).toBe(mockHandleSecretCreated);
    });

    it('passes with-expiry prop to SecretForm', () => {
      const wrapper = createWrapper();
      const secretForm = wrapper.findComponent(SecretFormStub);
      expect(secretForm.props('withExpiry')).toBe(true);
    });

    it('wires handleCloseModal to modal close event', async () => {
      mockModalData.value = {
        shareUrl: 'https://example.com/secret/abc123',
        naturalExpiration: '24 hours',
        hasPassphrase: false,
        metadataKey: 'testkey123',
        secretShortkey: 'abc123',
      };
      mockShowModal.value = true;

      const wrapper = createWrapper();
      await nextTick();

      const modal = wrapper.findComponent(CopyFirstModalStub);
      modal.vm.$emit('close');

      expect(mockHandleCloseModal).toHaveBeenCalledTimes(1);
    });
  });
});
