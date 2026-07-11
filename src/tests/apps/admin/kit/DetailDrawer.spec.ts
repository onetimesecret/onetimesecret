// src/tests/apps/admin/kit/DetailDrawer.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import DetailDrawer from '@/apps/admin/components/kit/DetailDrawer.vue';
import { createTestI18n } from '@tests/setup';

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
    template: '<h2><slot /></h2>',
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

describe('DetailDrawer (record slide-over)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  const mountDrawer = (props: Record<string, unknown> = {}, slots: Record<string, string> = {}) =>
    mount(DetailDrawer, {
      props: { open: true, ...props },
      slots,
      global: { plugins: [i18n] },
    });

  it('renders content when open', () => {
    wrapper = mountDrawer({ title: 'Customer detail' }, { default: '<p class="body">Body</p>' });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    expect(wrapper.find('.body').exists()).toBe(true);
    expect(wrapper.text()).toContain('Customer detail');
  });

  it('does not render content when closed', () => {
    wrapper = mountDrawer({ open: false });
    expect(wrapper.find('.dialog-panel').exists()).toBe(false);
  });

  it('renders the subtitle when provided', () => {
    wrapper = mountDrawer({ title: 'T', subtitle: 'ID: cust_123' });
    expect(wrapper.text()).toContain('ID: cust_123');
  });

  it('emits update:open=false and close when the close button is clicked', async () => {
    wrapper = mountDrawer({ title: 'T' });
    const closeBtn = wrapper.findAll('button').find((b) => b.attributes('aria-label'));
    await closeBtn!.trigger('click');
    expect(wrapper.emitted('update:open')![0]).toEqual([false]);
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('emits close when the dialog requests close (Escape / backdrop)', async () => {
    wrapper = mountDrawer();
    await wrapper.find('[role="dialog"]').trigger('close');
    expect(wrapper.emitted('close')).toBeTruthy();
    expect(wrapper.emitted('update:open')![0]).toEqual([false]);
  });

  it('renders a footer slot when supplied', () => {
    wrapper = mountDrawer({ title: 'T' }, { footer: '<div class="drawer-footer">Actions</div>' });
    expect(wrapper.find('.drawer-footer').exists()).toBe(true);
  });

  it('allows overriding the header via the header slot', () => {
    wrapper = mountDrawer({ title: 'ignored' }, { header: '<div class="custom-head">Custom</div>' });
    expect(wrapper.find('.custom-head').exists()).toBe(true);
  });
});
