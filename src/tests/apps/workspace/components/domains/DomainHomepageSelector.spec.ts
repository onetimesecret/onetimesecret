// src/tests/apps/workspace/components/domains/DomainHomepageSelector.spec.ts

import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import DomainHomepageSelector from '@/apps/workspace/components/domains/DomainHomepageSelector.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name'],
  },
}));

const INCOMING_ROUTE = { name: 'DomainIncoming', params: { orgid: 'org_1', extid: 'cd_1' } };

function mountSelector(props: Record<string, unknown> = {}, attachTo?: HTMLElement) {
  return mount(DomainHomepageSelector, {
    attachTo,
    props: {
      modelValue: 'private',
      incomingConfigRoute: INCOMING_ROUTE,
      ...props,
    },
    global: {
      stubs: {
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
}

describe('DomainHomepageSelector', () => {
  it('renders private and create options; hides incoming when unavailable', () => {
    const wrapper = mountSelector({ incomingAvailable: false });

    expect(wrapper.find('[data-testid="homepage-option-private"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="homepage-option-create"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="homepage-option-incoming"]').exists()).toBe(false);
  });

  it('marks the current selection checked', () => {
    const wrapper = mountSelector({ modelValue: 'create' });

    expect(
      wrapper.find('[data-testid="homepage-option-create"]').attributes('aria-checked')
    ).toBe('true');
    expect(
      wrapper.find('[data-testid="homepage-option-private"]').attributes('aria-checked')
    ).toBe('false');
  });

  it('emits update:modelValue when selecting an enabled option', async () => {
    const wrapper = mountSelector({ modelValue: 'private' });

    await wrapper.find('[data-testid="homepage-option-create"]').trigger('click');

    expect(wrapper.emitted('update:modelValue')).toEqual([['create']]);
  });

  it('does not emit when re-selecting the current option', async () => {
    const wrapper = mountSelector({ modelValue: 'create' });

    await wrapper.find('[data-testid="homepage-option-create"]').trigger('click');

    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('disables the incoming option and shows the recipients hint while unready', async () => {
    const wrapper = mountSelector({
      modelValue: 'private',
      incomingAvailable: true,
      incomingReady: false,
    });

    const incoming = wrapper.find('[data-testid="homepage-option-incoming"]');
    expect(incoming.attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-testid="homepage-incoming-unready-hint"]').exists()).toBe(true);

    await incoming.trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('allows selecting incoming once ready', async () => {
    const wrapper = mountSelector({
      modelValue: 'create',
      incomingAvailable: true,
      incomingReady: true,
    });

    expect(wrapper.find('[data-testid="homepage-incoming-unready-hint"]').exists()).toBe(false);

    await wrapper.find('[data-testid="homepage-option-incoming"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['incoming']]);
  });

  it('disables every option when the group is disabled (save in flight)', async () => {
    const wrapper = mountSelector({
      modelValue: 'private',
      disabled: true,
      incomingAvailable: true,
      incomingReady: true,
    });

    for (const key of ['private', 'create', 'incoming']) {
      expect(
        wrapper.find(`[data-testid="homepage-option-${key}"]`).attributes('disabled')
      ).toBeDefined();
    }

    await wrapper.find('[data-testid="homepage-option-create"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('moves selection between enabled options with arrow keys, skipping disabled ones', async () => {
    const wrapper = mountSelector({
      modelValue: 'create',
      incomingAvailable: true,
      incomingReady: false, // incoming disabled — arrows must skip it
    });

    await wrapper.find('[role="radiogroup"]').trigger('keydown', { key: 'ArrowDown' });

    // create -> (skip incoming) -> wraps to private
    expect(wrapper.emitted('update:modelValue')).toEqual([['private']]);
  });

  it('moves DOM focus with the selection when navigating by keyboard', async () => {
    // WAI-ARIA radiogroups move focus with the arrows; without it the
    // selection moves but focus stays put, so Space/Enter re-activates the
    // previously focused option.
    const wrapper = mountSelector({ modelValue: 'private' }, document.body);

    await wrapper.find('[role="radiogroup"]').trigger('keydown', { key: 'ArrowDown' });
    await flushPromises();

    expect(document.activeElement).toBe(
      wrapper.find('[data-testid="homepage-option-create"]').element
    );

    wrapper.unmount();
  });

  it('restores focus to the tab stop after a save-driven disable clears', async () => {
    // Selecting kicks off a save that disables (and blurs) the group; when it
    // re-enables the keyboard user must not be dropped onto <body>.
    const wrapper = mountSelector({ modelValue: 'private' }, document.body);

    await wrapper.find('[role="radiogroup"]').trigger('keydown', { key: 'ArrowDown' });
    // Save in flight: group disabled, active button blurred.
    await wrapper.setProps({ disabled: true });
    (document.activeElement as HTMLElement | null)?.blur();
    // Save resolves; the selection commits and the group re-enables.
    await wrapper.setProps({ disabled: false, modelValue: 'create' });
    await flushPromises();

    expect(document.activeElement).toBe(
      wrapper.find('[data-testid="homepage-option-create"]').element
    );

    wrapper.unmount();
  });

  it('does not steal focus into the group when re-enabling after a pointer selection', async () => {
    const wrapper = mountSelector({ modelValue: 'private' }, document.body);

    // Pointer selection must clear any keyboard-restore intent.
    await wrapper.find('[data-testid="homepage-option-create"]').trigger('click');
    await wrapper.setProps({ disabled: true });
    (document.activeElement as HTMLElement | null)?.blur();
    await wrapper.setProps({ disabled: false, modelValue: 'create' });
    await flushPromises();

    expect(document.activeElement).toBe(document.body);

    wrapper.unmount();
  });

  it('keeps a tab stop and sane arrow movement when the stored selection is disabled', async () => {
    // Drift state: stored mode 'incoming' while incoming became unready. The
    // selected option renders disabled; the group must stay keyboard-usable.
    const wrapper = mountSelector({
      modelValue: 'incoming',
      incomingAvailable: true,
      incomingReady: false,
    });

    // First enabled option takes the tab stop (disabled buttons drop out of
    // the tab order regardless of tabindex).
    expect(
      wrapper.find('[data-testid="homepage-option-private"]').attributes('tabindex')
    ).toBe('0');
    expect(
      wrapper.find('[data-testid="homepage-option-incoming"]').attributes('tabindex')
    ).toBe('-1');

    // Arrow movement is anchored to the tab stop, not the disabled selection:
    // private -> create.
    await wrapper.find('[role="radiogroup"]').trigger('keydown', { key: 'ArrowDown' });
    expect(wrapper.emitted('update:modelValue')).toEqual([['create']]);
  });
});
