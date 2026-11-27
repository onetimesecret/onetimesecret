// src/tests/shared/components/modals/ConfirmDialog.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
import { createTestI18n } from '@tests/setup';

// The focus trap needs real layout to find tabbable nodes; render its slot.
vi.mock('focus-trap-vue', () => ({
  FocusTrap: {
    name: 'FocusTrap',
    template: '<div><slot /></div>',
    props: ['active', 'initialFocus', 'escapeDeactivates', 'clickOutsideDeactivates', 'allowOutsideClick'],
    emits: ['deactivate'],
  },
}));

const i18n = createTestI18n();

// Stands in for a settings card: `backdrop-filter` on an ancestor makes it the
// containing block for fixed descendants.
const BlurredCard = defineComponent({
  components: { ConfirmDialog },
  emits: ['confirm', 'cancel'],
  setup(_, { emit }) {
    return () =>
      h('section', { class: 'backdrop-blur-sm', 'data-testid': 'card' }, [
        h(ConfirmDialog, {
          title: 'Title',
          message: 'Message',
          onConfirm: () => emit('confirm'),
          onCancel: () => emit('cancel'),
        }),
      ]);
  },
});

describe('ConfirmDialog', () => {
  let wrapper: VueWrapper;

  const mountInCard = () => {
    wrapper = mount(BlurredCard, { attachTo: document.body, global: { plugins: [i18n] } });
  };

  const dialog = () => document.body.querySelector<HTMLElement>('[role="dialog"]');

  afterEach(() => {
    wrapper?.unmount();
  });

  it('renders the overlay as a child of body, outside the card that hosts it', () => {
    mountInCard();

    expect(dialog()).not.toBeNull();
    expect(dialog()!.parentElement).toBe(document.body);
    expect(wrapper.find('[data-testid="card"]').element.contains(dialog())).toBe(false);
  });

  it('keeps the dialog semantics and labelling', () => {
    mountInCard();

    expect(dialog()!.getAttribute('aria-modal')).toBe('true');
    expect(dialog()!.getAttribute('aria-labelledby')).toBe('confirm-dialog-title');
    expect(document.getElementById('confirm-dialog-title')!.textContent).toContain('Title');
    expect(document.getElementById('confirm-dialog-message')!.textContent).toContain('Message');
  });

  it('gives the trap the Cancel button for initial focus', () => {
    mountInCard();
    const trap = wrapper.findComponent({ name: 'FocusTrap' });
    expect(trap.props('initialFocus')()).toBe(dialog()!.querySelector('[data-testid="confirm-dialog-cancel"]'));
  });

  it('emits confirm and removes the overlay', async () => {
    mountInCard();

    document.body.querySelector<HTMLElement>('[data-testid="confirm-dialog-confirm"]')!.click();
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('confirm')).toHaveLength(1);
    expect(dialog()).toBeNull();
  });

  it('emits cancel and removes the overlay', async () => {
    mountInCard();

    document.body.querySelector<HTMLElement>('[data-testid="confirm-dialog-cancel"]')!.click();
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(dialog()).toBeNull();
  });

  it('emits cancel when the backdrop is clicked', async () => {
    mountInCard();

    dialog()!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    dialog()!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(dialog()).toBeNull();
  });

  it('lets clicks outside the panel through the focus trap', () => {
    mountInCard();

    // focus-trap swallows outside clicks unless allowed, so the backdrop
    // handler would never run in a browser.
    expect(wrapper.findComponent({ name: 'FocusTrap' }).props('allowOutsideClick')).toBe(true);
  });

  it('stays open when a press inside the panel is released over the backdrop', async () => {
    mountInCard();

    document.body
      .querySelector<HTMLElement>('[data-testid="confirm-dialog"]')!
      .dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    dialog()!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('cancel')).toBeUndefined();
    expect(dialog()).not.toBeNull();
  });

  it('ignores clicks inside the panel', async () => {
    mountInCard();

    document.body.querySelector<HTMLElement>('[data-testid="confirm-dialog"]')!.click();
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('cancel')).toBeUndefined();
    expect(dialog()).not.toBeNull();
  });

  it('emits cancel when Escape deactivates the focus trap', async () => {
    mountInCard();

    wrapper.findComponent({ name: 'FocusTrap' }).vm.$emit('deactivate');
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(dialog()).toBeNull();
  });

  it('does not emit cancel when the trap deactivates after confirm', async () => {
    mountInCard();
    const trap = wrapper.findComponent({ name: 'FocusTrap' });

    document.body.querySelector<HTMLElement>('[data-testid="confirm-dialog-confirm"]')!.click();
    trap.vm.$emit('deactivate');
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('confirm')).toHaveLength(1);
    expect(wrapper.emitted('cancel')).toBeUndefined();
  });

  it('removes the overlay from body when the host unmounts', () => {
    mountInCard();
    wrapper.unmount();

    expect(dialog()).toBeNull();
  });
});
