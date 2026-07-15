// src/tests/apps/admin/kit/AdminConfirmDialog.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';

import AdminConfirmDialog from '@/apps/admin/components/kit/AdminConfirmDialog.vue';
import { createTestI18n } from '@tests/setup';

// Mock HeadlessUI so the dialog markup renders synchronously in jsdom.
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

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

const i18n = createTestI18n();

describe('AdminConfirmDialog (CONTRACT 4 — typed-confirmation gate)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  const mountDialog = (props: Record<string, unknown> = {}) =>
    mount(AdminConfirmDialog, {
      props: { open: true, title: 'Delete customer', ...props },
      global: { plugins: [i18n] },
    });

  const submitBtn = () => wrapper.find('[data-testid="admin-confirm-submit"]');
  const cancelBtn = () => wrapper.find('[data-testid="admin-confirm-cancel"]');
  const typedInput = () => wrapper.find('#admin-confirm-input');

  describe('typed-confirmation mode (confirmToken provided)', () => {
    it('renders the typed input when a confirmToken is set', () => {
      wrapper = mountDialog({ confirmToken: 'alice@example.com' });
      expect(typedInput().exists()).toBe(true);
    });

    it('DISABLES confirm until the typed input EXACTLY equals confirmToken', async () => {
      wrapper = mountDialog({ confirmToken: 'alice@example.com' });

      // Initially disabled (empty input).
      expect(submitBtn().attributes('disabled')).toBeDefined();

      // Partial / wrong input stays disabled.
      await typedInput().setValue('alice@example.co');
      expect(submitBtn().attributes('disabled')).toBeDefined();

      // Exact match enables.
      await typedInput().setValue('alice@example.com');
      expect(submitBtn().attributes('disabled')).toBeUndefined();
    });

    it('treats the match as case-sensitive with NO trimming', async () => {
      wrapper = mountDialog({ confirmToken: 'alice@example.com' });

      await typedInput().setValue('ALICE@example.com');
      expect(submitBtn().attributes('disabled')).toBeDefined();

      await typedInput().setValue('alice@example.com ');
      expect(submitBtn().attributes('disabled')).toBeDefined();

      await typedInput().setValue('alice@example.com');
      expect(submitBtn().attributes('disabled')).toBeUndefined();
    });

    it('re-disables confirm if the input diverges again', async () => {
      wrapper = mountDialog({ confirmToken: 'tok-123' });
      await typedInput().setValue('tok-123');
      expect(submitBtn().attributes('disabled')).toBeUndefined();
      await typedInput().setValue('tok-12');
      expect(submitBtn().attributes('disabled')).toBeDefined();
    });

    it('does NOT emit confirm when submitted while the token is unmatched', async () => {
      wrapper = mountDialog({ confirmToken: 'tok-123' });
      await typedInput().setValue('nope');
      await wrapper.find('form').trigger('submit');
      expect(wrapper.emitted('confirm')).toBeFalsy();
    });

    it('emits confirm on submit once the token matches exactly', async () => {
      wrapper = mountDialog({ confirmToken: 'tok-123' });
      await typedInput().setValue('tok-123');
      await wrapper.find('form').trigger('submit');
      expect(wrapper.emitted('confirm')).toBeTruthy();
      expect(wrapper.emitted('confirm')![0]).toEqual([]);
    });

    it('uses the confirmToken as the input placeholder', () => {
      wrapper = mountDialog({ confirmToken: 'alice@example.com' });
      expect(typedInput().attributes('placeholder')).toBe('alice@example.com');
    });

    it('clears the typed value when the dialog closes and reopens', async () => {
      wrapper = mountDialog({ confirmToken: 'tok-123' });
      await typedInput().setValue('tok-123');
      expect((typedInput().element as HTMLInputElement).value).toBe('tok-123');

      await wrapper.setProps({ open: false });
      await nextTick();
      await wrapper.setProps({ open: true });
      await nextTick();

      expect((typedInput().element as HTMLInputElement).value).toBe('');
      // And confirm is disabled again after the reset.
      expect(submitBtn().attributes('disabled')).toBeDefined();
    });
  });

  describe('simple confirm mode (no confirmToken)', () => {
    it('renders NO typed input', () => {
      wrapper = mountDialog();
      expect(typedInput().exists()).toBe(false);
    });

    it('treats an empty-string confirmToken as simple mode', () => {
      wrapper = mountDialog({ confirmToken: '' });
      expect(typedInput().exists()).toBe(false);
      expect(submitBtn().attributes('disabled')).toBeUndefined();
    });

    it('leaves confirm ENABLED by default', () => {
      wrapper = mountDialog();
      expect(submitBtn().attributes('disabled')).toBeUndefined();
    });

    it('emits confirm immediately on submit', async () => {
      wrapper = mountDialog();
      await wrapper.find('form').trigger('submit');
      expect(wrapper.emitted('confirm')).toBeTruthy();
    });
  });

  describe('loading state', () => {
    it('disables confirm and cancel while loading', () => {
      wrapper = mountDialog({ confirmToken: 'tok', loading: true });
      expect(submitBtn().attributes('disabled')).toBeDefined();
      expect(cancelBtn().attributes('disabled')).toBeDefined();
    });

    it('keeps confirm disabled while loading even when the token matches', async () => {
      wrapper = mountDialog({ confirmToken: 'tok', loading: false });
      await typedInput().setValue('tok');
      expect(submitBtn().attributes('disabled')).toBeUndefined();
      await wrapper.setProps({ loading: true });
      expect(submitBtn().attributes('disabled')).toBeDefined();
    });

    it('shows processing text and a spinner while loading', () => {
      wrapper = mountDialog({ loading: true });
      expect(wrapper.text()).toContain('web.COMMON.processing');
      expect(wrapper.find('.o-icon[data-name="arrow-path"]').exists()).toBe(true);
    });
  });

  describe('error + variant', () => {
    it('renders the error via an alert region', () => {
      wrapper = mountDialog({ error: 'Customer not found' });
      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('Customer not found');
    });

    it('renders no alert when error is null', () => {
      wrapper = mountDialog({ error: null });
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    });

    it('applies danger styling to confirm when variant is danger', () => {
      wrapper = mountDialog({ variant: 'danger' });
      expect(submitBtn().classes().join(' ')).toContain('bg-red');
    });

    it('applies brand styling by default', () => {
      wrapper = mountDialog();
      expect(submitBtn().classes().join(' ')).toContain('bg-brand');
    });

    it('renders the description prop', () => {
      wrapper = mountDialog({ description: 'This permanently deletes the account.' });
      expect(wrapper.text()).toContain('This permanently deletes the account.');
    });
  });

  describe('cancel / dismiss', () => {
    it('emits cancel and update:open=false when cancel is clicked', async () => {
      wrapper = mountDialog({ confirmToken: 'tok' });
      await cancelBtn().trigger('click');
      expect(wrapper.emitted('cancel')).toBeTruthy();
      expect(wrapper.emitted('update:open')).toBeTruthy();
      expect(wrapper.emitted('update:open')![0]).toEqual([false]);
    });

    it('emits cancel when the dialog requests close (Escape / backdrop)', async () => {
      wrapper = mountDialog();
      await wrapper.find('[role="dialog"]').trigger('close');
      expect(wrapper.emitted('cancel')).toBeTruthy();
    });
  });
});
