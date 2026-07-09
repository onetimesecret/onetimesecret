// src/tests/shared/components/navigation/ScopeSwitcher.spec.ts

/**
 * Unit tests for the featurized <ScopeSwitcher> engine.
 *
 * These exercise the engine's contract in isolation (independent of the
 * Organization/Domain adapters) against the REAL @headlessui/vue Menu:
 *   - it renders normalized items and reflects current/disabled state
 *   - `select` is emitted AND the dropdown closes
 *   - the gear button emits `open-settings`, stops row selection, and closes
 *     (the exact interaction that used to regress in the copy-pasted switchers)
 *   - disabled rows neither select nor navigate
 *   - `canManage` gates the divider + footer region
 *   - the header/visual/badge/footer slots render adapter content
 *
 * Only OIcon is stubbed; HeadlessUI is real so open/close is genuinely tested.
 */

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { h, nextTick } from 'vue';
import ScopeSwitcher from '@/shared/components/navigation/ScopeSwitcher.vue';
import type { ScopeSwitcherItem } from '@/shared/components/navigation/scopeSwitcher';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class', 'ariaLabel'],
  },
}));

const items: ScopeSwitcherItem[] = [
  { id: 'a', label: 'Alpha', isCurrent: true, hasSettings: true },
  { id: 'b', label: 'Beta', isCurrent: false, hasSettings: true },
  { id: 'c', label: 'Canonical', isCurrent: false, disabled: true, disabledReason: 'no settings' },
];

const baseProps = {
  items,
  header: 'MY SCOPES',
  triggerAriaLabel: 'Switch scope',
  lockedTitle: 'Locked',
  settingsLabel: 'Scope settings',
  testid: 'scope-switcher',
  itemTestid: 'scope-item',
};

const dropdown = (w: VueWrapper) => w.find('[data-testid="scope-switcher-dropdown"]');

async function openMenu(w: VueWrapper) {
  await w.get('[data-testid="scope-switcher-trigger"]').trigger('click');
  await nextTick();
  await flushPromises();
  expect(dropdown(w).exists()).toBe(true);
}

describe('ScopeSwitcher engine', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('renders a row per item with the id-based test id', async () => {
    wrapper = mount(ScopeSwitcher, { props: baseProps, attachTo: document.body });
    await openMenu(wrapper);

    expect(wrapper.get('[data-testid="scope-item-a"]').text()).toContain('Alpha');
    expect(wrapper.get('[data-testid="scope-item-b"]').text()).toContain('Beta');
    expect(wrapper.find('[data-testid="scope-item-c"]').exists()).toBe(true);
  });

  it('emits select and closes the dropdown when a row is clicked', async () => {
    wrapper = mount(ScopeSwitcher, { props: baseProps, attachTo: document.body });
    await openMenu(wrapper);

    await wrapper.get('[data-testid="scope-item-b"]').trigger('click');
    await nextTick();
    await flushPromises();

    expect(wrapper.emitted('select')?.[0]).toEqual(['b']);
    expect(dropdown(wrapper).exists()).toBe(false);
  });

  it('emits open-settings, does not select, and closes when the gear is clicked', async () => {
    wrapper = mount(ScopeSwitcher, { props: baseProps, attachTo: document.body });
    await openMenu(wrapper);

    // Gear on the non-current row 'b' (its checkmark is absent, gear is present).
    await wrapper
      .get('[data-testid="scope-item-b"] [aria-label="Scope settings"]')
      .trigger('click');
    await nextTick();
    await flushPromises();

    expect(wrapper.emitted('open-settings')?.[0]).toEqual(['b']);
    // stopPropagation must keep the row's own select from firing.
    expect(wrapper.emitted('select')).toBeUndefined();
    expect(dropdown(wrapper).exists()).toBe(false);
  });

  it('does not emit select for a disabled row', async () => {
    wrapper = mount(ScopeSwitcher, { props: baseProps, attachTo: document.body });
    await openMenu(wrapper);

    await wrapper.get('[data-testid="scope-item-c"]').trigger('click');
    await nextTick();
    await flushPromises();

    expect(wrapper.emitted('select')).toBeUndefined();
  });

  it('hides the divider + footer region unless canManage is true', async () => {
    wrapper = mount(ScopeSwitcher, {
      props: baseProps,
      slots: { footer: () => h('div', { 'data-testid': 'ftr' }, 'Manage') },
      attachTo: document.body,
    });
    await openMenu(wrapper);
    expect(wrapper.find('[data-testid="ftr"]').exists()).toBe(false);

    wrapper.unmount();

    wrapper = mount(ScopeSwitcher, {
      props: { ...baseProps, canManage: true },
      slots: { footer: () => h('div', { 'data-testid': 'ftr' }, 'Manage') },
      attachTo: document.body,
    });
    await openMenu(wrapper);
    expect(wrapper.find('[data-testid="ftr"]').exists()).toBe(true);
  });

  it('renders trigger, item-visual, and badge slot content', async () => {
    wrapper = mount(ScopeSwitcher, {
      props: baseProps,
      slots: {
        trigger: () => h('span', { 'data-testid': 'trigger-visual' }, 'TRIG'),
        'item-visual': (p: { item: ScopeSwitcherItem }) =>
          h('span', { class: 'ivis' }, p.item.id),
        'item-badge': (p: { item: ScopeSwitcherItem }) =>
          p.item.id === 'a' ? h('span', { 'data-testid': 'badge-a' }, 'PAID') : null,
      },
      attachTo: document.body,
    });

    expect(wrapper.get('[data-testid="scope-switcher-trigger"]').text()).toContain('TRIG');

    await openMenu(wrapper);
    expect(wrapper.findAll('.ivis').length).toBe(items.length);
    expect(wrapper.find('[data-testid="badge-a"]').exists()).toBe(true);
  });

  it('disables the trigger when locked', () => {
    wrapper = mount(ScopeSwitcher, {
      props: { ...baseProps, locked: true },
      attachTo: document.body,
    });
    const trigger = wrapper.get('[data-testid="scope-switcher-trigger"]');
    expect((trigger.element as HTMLButtonElement).disabled).toBe(true);
    expect(trigger.attributes('title')).toBe('Locked');
  });
});
