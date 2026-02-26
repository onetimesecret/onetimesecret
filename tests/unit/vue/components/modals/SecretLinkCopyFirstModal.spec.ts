// tests/unit/vue/components/modals/SecretLinkCopyFirstModal.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia } from 'pinia';
import { ref } from 'vue';
import SecretLinkCopyFirstModal from '@/components/modals/SecretLinkCopyFirstModal.vue';

// Mock the metadata store. The component accesses `metadataStore.record`
// through a computed, so we provide plain reactive-compatible values.
// Using `vi.hoisted` ensures the data is available when the hoisted
// vi.mock factory executes.
const { mockStoreRecord, mockStoreDetails } = vi.hoisted(() => ({
  mockStoreRecord: {
    key: 'testkey123',
    shortkey: 'abc123',
    state: 'new',
    created: new Date('2024-12-25T16:06:54Z'),
    updated: new Date('2024-12-26T09:06:54Z'),
    expiration_in_seconds: 86400,
  },
  mockStoreDetails: {
    type: 'record',
    has_passphrase: false,
  },
}));

vi.mock('@/stores/metadataStore', () => ({
  useMetadataStore: () => ({
    record: mockStoreRecord,
    details: mockStoreDetails,
    fetch: vi.fn().mockResolvedValue(undefined),
  }),
}));

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

function createWrapper(props = {}) {
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        'web.LABELS.close': 'Close',
        'web.LABELS.secret_link': 'Secret Link',
        'web.LABELS.expiration_time': 'Expires',
        'web.LABELS.expires_in': 'Expires in {time}',
        'web.LABELS.passphrase_protected': 'Passphrase protected',
        'web.LABELS.view_details': 'View full details',
        'web.LABELS.hide_details': 'Hide details',
        'web.COMMON.share_link_securely': 'Share this link securely',
        'web.private.created_success': 'Secret link created',
      },
    },
  });

  const pinia = createPinia();

  return mount(SecretLinkCopyFirstModal, {
    props: {
      show: true,
      shareUrl: 'https://example.com/secret/abc123',
      naturalExpiration: '24 hours',
      hasPassphrase: false,
      metadataKey: 'testkey123',
      secretShortkey: 'abc123',
      ...props,
    },
    global: {
      plugins: [i18n, pinia],
      stubs: {
        RouterLink: {
          template: '<a :href="to"><slot /></a>',
          props: ['to'],
        },
        OIcon: { template: '<span />' },
        CopyButton: {
          name: 'CopyButton',
          template: '<button class="copy-btn" />',
          props: ['text'],
        },
        StatusBadge: { template: '<span />' },
        Transition: {
          template: '<div><slot /></div>',
        },
      },
    },
  });
}

describe('SecretLinkCopyFirstModal', () => {
  it('renders when show is true', () => {
    const wrapper = createWrapper();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
  });

  it('is hidden when show is false', () => {
    const wrapper = createWrapper({ show: false });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });

  it('displays the share URL in a textarea', () => {
    const wrapper = createWrapper();
    const textarea = wrapper.find('textarea');
    expect(textarea.exists()).toBe(true);
    expect(textarea.element.value).toBe('https://example.com/secret/abc123');
    expect(textarea.attributes('readonly')).toBeDefined();
  });

  it('displays the natural expiration text', () => {
    const wrapper = createWrapper();
    expect(wrapper.text()).toContain('24 hours');
  });

  it('displays the secret shortkey', () => {
    const wrapper = createWrapper();
    expect(wrapper.text()).toContain('abc123');
  });

  it('shows passphrase badge when hasPassphrase is true', () => {
    const wrapper = createWrapper({ hasPassphrase: true });
    expect(wrapper.text()).toContain('Passphrase protected');
  });

  it('hides passphrase badge when hasPassphrase is false', () => {
    const wrapper = createWrapper({ hasPassphrase: false });
    expect(wrapper.text()).not.toContain('Passphrase protected');
  });

  it('renders view full details link with correct href', async () => {
    const wrapper = createWrapper();
    // The receipt link is inside the collapsible details panel.
    // Click the toggle button to expand it first.
    const toggleBtn = wrapper.find('button[aria-expanded="false"]');
    await toggleBtn.trigger('click');

    const link = wrapper.find('a[href="/receipt/testkey123"]');
    expect(link.exists()).toBe(true);
    expect(link.text()).toContain('View full details');
  });

  it('passes correct text prop to CopyButton', () => {
    const wrapper = createWrapper();
    const copyBtn = wrapper.findComponent({ name: 'CopyButton' });
    expect(copyBtn.exists()).toBe(true);
    expect(copyBtn.props('text')).toBe('https://example.com/secret/abc123');
  });

  it('emits close when X button is clicked', async () => {
    const wrapper = createWrapper();
    const closeBtn = wrapper.find('button[aria-label="Close"]');
    await closeBtn.trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
