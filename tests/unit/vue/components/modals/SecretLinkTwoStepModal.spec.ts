// tests/unit/vue/components/modals/SecretLinkTwoStepModal.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { createI18n } from 'vue-i18n';
import SecretLinkTwoStepModal from '@/components/modals/SecretLinkTwoStepModal.vue';

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
        'web.LABELS.show_details': 'Show details',
        'web.LABELS.hide_details': 'Hide details',
        'web.COMMON.share_link_securely': 'Share this link securely',
        'web.private.created_success': 'Secret link created',
      },
    },
  });

  return mount(SecretLinkTwoStepModal, {
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
      plugins: [i18n],
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
        Transition: {
          template: '<div><slot /></div>',
        },
      },
    },
  });
}

describe('SecretLinkTwoStepModal', () => {
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
  });

  it('passes correct text prop to CopyButton', () => {
    const wrapper = createWrapper();
    const copyBtn = wrapper.findComponent({ name: 'CopyButton' });
    expect(copyBtn.exists()).toBe(true);
    expect(copyBtn.props('text')).toBe('https://example.com/secret/abc123');
  });

  it('starts on step 1 with only copy UI visible', () => {
    const wrapper = createWrapper();
    expect(wrapper.text()).toContain('Show details');
    expect(wrapper.find('#secret-link-details-panel').exists()).toBe(false);
  });

  it('transitions to step 2 when "Show details" is clicked', async () => {
    const wrapper = createWrapper();
    const toggleBtn = wrapper.find('button[aria-expanded="false"]');
    expect(toggleBtn.exists()).toBe(true);

    await toggleBtn.trigger('click');

    expect(wrapper.find('#secret-link-details-panel').exists()).toBe(true);
    expect(wrapper.text()).toContain('Expires in 24 hours');
  });

  it('shows passphrase badge in step 2 when hasPassphrase is true', async () => {
    const wrapper = createWrapper({ hasPassphrase: true });
    const toggleBtn = wrapper.find('button[aria-expanded="false"]');
    await toggleBtn.trigger('click');

    expect(wrapper.text()).toContain('Passphrase protected');
  });

  it('shows receipt link in step 2', async () => {
    const wrapper = createWrapper();
    const toggleBtn = wrapper.find('button[aria-expanded="false"]');
    await toggleBtn.trigger('click');

    const link = wrapper.find('a[href="/receipt/testkey123"]');
    expect(link.exists()).toBe(true);
    expect(link.text()).toContain('View full details');
  });

  it('toggles aria-expanded correctly', async () => {
    const wrapper = createWrapper();
    let toggleBtn = wrapper.find('button[aria-controls="secret-link-details-panel"]');
    expect(toggleBtn.attributes('aria-expanded')).toBe('false');

    await toggleBtn.trigger('click');
    toggleBtn = wrapper.find('button[aria-controls="secret-link-details-panel"]');
    expect(toggleBtn.attributes('aria-expanded')).toBe('true');
  });

  it('resets to step 1 when reopened', async () => {
    const wrapper = createWrapper();

    const toggleBtn = wrapper.find('button[aria-expanded="false"]');
    await toggleBtn.trigger('click');
    expect(wrapper.find('#secret-link-details-panel').exists()).toBe(true);

    await wrapper.setProps({ show: false });
    await wrapper.setProps({ show: true });

    expect(wrapper.find('#secret-link-details-panel').exists()).toBe(false);
  });

  it('emits close when X button is clicked', async () => {
    const wrapper = createWrapper();
    const closeBtn = wrapper.find('button[aria-label="Close"]');
    await closeBtn.trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
