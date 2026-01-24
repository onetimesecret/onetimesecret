// src/tests/shared/components/modals/PasswordConfirmModal.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import PasswordConfirmModal from '@/shared/components/modals/PasswordConfirmModal.vue';
import { nextTick } from 'vue';

// Mock HeadlessUI components
vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog" @close="$emit(\'close\')"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: {
    name: 'DialogTitle',
    template: '<h3><slot /></h3>',
    props: ['as', 'class'],
  },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: {
    name: 'TransitionChild',
    template: '<div><slot /></div>',
    props: ['as', 'enter', 'enterFrom', 'enterTo', 'leave', 'leaveFrom', 'leaveTo'],
  },
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        COMMON: {
          word_confirm: 'Confirm',
          word_cancel: 'Cancel',
          processing: 'Processing...',
          field_password: 'Password',
          password_placeholder: 'Enter your password',
          show_password: 'Show password',
          hide_password: 'Hide password',
        },
      },
    },
  },
});

describe('PasswordConfirmModal', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (props: Record<string, unknown> = {}) => {
    return mount(PasswordConfirmModal, {
      props: {
        open: true,
        title: 'Confirm Action',
        ...props,
      },
      global: {
        plugins: [i18n],
      },
    });
  };

  describe('Rendering', () => {
    it('renders the modal when open prop is true', () => {
      wrapper = mountComponent({ open: true });
      expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    });

    it('does not render content when open prop is false', () => {
      wrapper = mountComponent({ open: false });
      expect(wrapper.find('.dialog-panel').exists()).toBe(false);
    });

    it('renders the title', () => {
      wrapper = mountComponent({ title: 'My Custom Title' });
      expect(wrapper.text()).toContain('My Custom Title');
    });

    it('renders the description when provided', () => {
      wrapper = mountComponent({
        title: 'Title',
        description: 'Please confirm your password',
      });
      expect(wrapper.text()).toContain('Please confirm your password');
    });

    it('does not render description when not provided', () => {
      wrapper = mountComponent({ title: 'Title' });
      // Should have title but no extra description text
      const html = wrapper.html();
      expect(html).toContain('Title');
    });

    it('renders password input field', () => {
      wrapper = mountComponent();
      const input = wrapper.find('input[type="password"]');
      expect(input.exists()).toBe(true);
    });

    it('renders confirm and cancel buttons', () => {
      wrapper = mountComponent();
      expect(wrapper.text()).toContain('Confirm');
      expect(wrapper.text()).toContain('Cancel');
    });

    it('renders lock icon by default', () => {
      wrapper = mountComponent();
      const icon = wrapper.find('.o-icon[data-name="lock-closed"]');
      expect(icon.exists()).toBe(true);
    });
  });

  describe('Password Input', () => {
    it('updates password value on input', async () => {
      wrapper = mountComponent();
      const input = wrapper.find('input');

      await input.setValue('mypassword123');

      expect((input.element as HTMLInputElement).value).toBe('mypassword123');
    });

    it('toggles password visibility when toggle button is clicked', async () => {
      wrapper = mountComponent();
      let input = wrapper.find('input');
      expect(input.attributes('type')).toBe('password');

      // Find and click the visibility toggle button
      const toggleButton = wrapper.findAll('button').find(btn =>
        btn.attributes('aria-label')?.includes('password')
      );
      expect(toggleButton).toBeDefined();

      await toggleButton!.trigger('click');
      await nextTick();

      input = wrapper.find('input');
      expect(input.attributes('type')).toBe('text');

      await toggleButton!.trigger('click');
      await nextTick();

      input = wrapper.find('input');
      expect(input.attributes('type')).toBe('password');
    });

    it('clears password when modal closes', async () => {
      wrapper = mountComponent({ open: true });
      const input = wrapper.find('input');

      await input.setValue('mypassword123');
      expect((input.element as HTMLInputElement).value).toBe('mypassword123');

      await wrapper.setProps({ open: false });
      await nextTick();

      await wrapper.setProps({ open: true });
      await nextTick();

      const newInput = wrapper.find('input');
      expect((newInput.element as HTMLInputElement).value).toBe('');
    });
  });

  describe('Button States', () => {
    it('disables confirm button when password is empty', () => {
      wrapper = mountComponent();
      const confirmButton = wrapper.find('button[type="submit"]');
      expect(confirmButton.attributes('disabled')).toBeDefined();
    });

    it('enables confirm button when password is entered', async () => {
      wrapper = mountComponent();
      const input = wrapper.find('input');

      await input.setValue('password123');
      await nextTick();

      const confirmButton = wrapper.find('button[type="submit"]');
      expect(confirmButton.attributes('disabled')).toBeUndefined();
    });

    it('disables all buttons during loading', async () => {
      wrapper = mountComponent({ loading: true });
      const input = wrapper.find('input');
      await input.setValue('password123');

      const buttons = wrapper.findAll('button');
      buttons.forEach(btn => {
        expect(btn.attributes('disabled')).toBeDefined();
      });
    });

    it('shows processing text during loading', () => {
      wrapper = mountComponent({ loading: true });
      expect(wrapper.text()).toContain('Processing...');
    });

    it('shows spinner during loading', () => {
      wrapper = mountComponent({ loading: true });
      const spinner = wrapper.find('.o-icon[data-name="arrow-path"]');
      expect(spinner.exists()).toBe(true);
    });
  });

  describe('Variant Styling', () => {
    it('applies default brand styling by default', () => {
      wrapper = mountComponent();
      const confirmButton = wrapper.find('button[type="submit"]');
      expect(confirmButton.classes().join(' ')).toContain('bg-brand');
    });

    it('applies danger styling when variant is danger', () => {
      wrapper = mountComponent({ variant: 'danger' });
      const confirmButton = wrapper.find('button[type="submit"]');
      expect(confirmButton.classes().join(' ')).toContain('bg-red');
    });

    it('applies danger styling to icon container when variant is danger', () => {
      wrapper = mountComponent({ variant: 'danger' });
      const iconContainer = wrapper.find('.bg-red-100, .dark\\:bg-red-900\\/30');
      expect(iconContainer.exists()).toBe(true);
    });
  });

  describe('Error Display', () => {
    it('displays error message when error prop is provided', () => {
      wrapper = mountComponent({ error: 'Invalid password' });
      expect(wrapper.text()).toContain('Invalid password');
    });

    it('does not display error when error prop is null', () => {
      wrapper = mountComponent({ error: null });
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    });

    it('shows error with proper ARIA attributes', () => {
      wrapper = mountComponent({ error: 'Error message' });
      const errorEl = wrapper.find('[role="alert"]');
      expect(errorEl.exists()).toBe(true);
      expect(errorEl.attributes('aria-live')).toBe('assertive');
    });

    it('links password input to error message via aria-describedby', () => {
      wrapper = mountComponent({ error: 'Error message' });
      const input = wrapper.find('input');
      expect(input.attributes('aria-describedby')).toBe('password-confirm-error');
      expect(input.attributes('aria-invalid')).toBe('true');
    });
  });

  describe('Events', () => {
    it('emits confirm event with password when form is submitted', async () => {
      wrapper = mountComponent();
      const input = wrapper.find('input');
      const form = wrapper.find('form');

      await input.setValue('mySecretPassword');
      await form.trigger('submit');

      expect(wrapper.emitted('confirm')).toBeTruthy();
      expect(wrapper.emitted('confirm')![0]).toEqual(['mySecretPassword']);
    });

    it('emits cancel event when cancel button is clicked', async () => {
      wrapper = mountComponent();
      const cancelButton = wrapper.findAll('button').find(btn =>
        btn.text().includes('Cancel')
      );

      await cancelButton!.trigger('click');

      expect(wrapper.emitted('cancel')).toBeTruthy();
    });

    it('emits update:open with false when cancel is clicked', async () => {
      wrapper = mountComponent();
      const cancelButton = wrapper.findAll('button').find(btn =>
        btn.text().includes('Cancel')
      );

      await cancelButton!.trigger('click');

      expect(wrapper.emitted('update:open')).toBeTruthy();
      expect(wrapper.emitted('update:open')![0]).toEqual([false]);
    });

    it('does not emit confirm when password is empty', async () => {
      wrapper = mountComponent();
      const form = wrapper.find('form');

      await form.trigger('submit');

      expect(wrapper.emitted('confirm')).toBeFalsy();
    });

    it('does not emit confirm when loading', async () => {
      wrapper = mountComponent({ loading: true });
      const input = wrapper.find('input');
      const form = wrapper.find('form');

      await input.setValue('password');
      await form.trigger('submit');

      expect(wrapper.emitted('confirm')).toBeFalsy();
    });
  });

  describe('Custom Button Text', () => {
    it('uses custom confirm text when provided', () => {
      wrapper = mountComponent({ confirmText: 'web.COMMON.word_confirm' });
      expect(wrapper.text()).toContain('Confirm');
    });

    it('uses custom cancel text when provided', () => {
      wrapper = mountComponent({ cancelText: 'web.COMMON.word_cancel' });
      expect(wrapper.text()).toContain('Cancel');
    });
  });

  describe('Accessibility', () => {
    it('has proper dialog role', () => {
      wrapper = mountComponent();
      expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    });

    it('password input has label', () => {
      wrapper = mountComponent();
      const label = wrapper.find('label[for="password-confirm-input"]');
      expect(label.exists()).toBe(true);
    });

    it('password toggle has aria-label', () => {
      wrapper = mountComponent();
      const toggleButton = wrapper.findAll('button').find(btn =>
        btn.attributes('aria-label')?.includes('password')
      );
      expect(toggleButton).toBeDefined();
      expect(toggleButton!.attributes('aria-label')).toContain('password');
    });

    it('disables input when loading', () => {
      wrapper = mountComponent({ loading: true });
      const input = wrapper.find('input');
      expect(input.attributes('disabled')).toBeDefined();
    });
  });

  describe('Slot Support', () => {
    it('allows custom icon via slot', () => {
      wrapper = mount(PasswordConfirmModal, {
        props: {
          open: true,
          title: 'Test',
        },
        slots: {
          icon: '<span class="custom-icon">Custom</span>',
        },
        global: {
          plugins: [i18n],
        },
      });

      expect(wrapper.find('.custom-icon').exists()).toBe(true);
    });

    it('allows custom description via slot', () => {
      wrapper = mount(PasswordConfirmModal, {
        props: {
          open: true,
          title: 'Test',
        },
        slots: {
          description: '<p class="custom-desc">Custom description</p>',
        },
        global: {
          plugins: [i18n],
        },
      });

      expect(wrapper.find('.custom-desc').exists()).toBe(true);
      expect(wrapper.text()).toContain('Custom description');
    });
  });
});
