// src/tests/apps/admin/kit/FilterBar.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import FilterBar from '@/apps/admin/components/kit/FilterBar.vue';
import type { FilterConfig } from '@/apps/admin/components/kit/types';
import { createTestI18n } from '@tests/setup';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

const filters: FilterConfig[] = [
  {
    key: 'role',
    label: 'Role',
    value: '',
    options: [
      { value: 'colonel', label: 'Colonel' },
      { value: 'customer', label: 'Customer' },
    ],
  },
];

const i18n = createTestI18n();

describe('FilterBar (config-driven filters)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  const mountBar = (props: Record<string, unknown> = {}, slots: Record<string, string> = {}) =>
    mount(FilterBar, { props, slots, global: { plugins: [i18n] } });

  it('renders a native <select> per filter config with an "all" option', () => {
    wrapper = mountBar({ filters });
    const select = wrapper.find('#kit-filter-role');
    expect(select.exists()).toBe(true);
    // all option + 2 configured options
    expect(select.findAll('option')).toHaveLength(3);
  });

  it('emits filter-change with (key, value) when a select changes', async () => {
    wrapper = mountBar({ filters });
    const select = wrapper.find('#kit-filter-role');
    await select.setValue('colonel');
    expect(wrapper.emitted('filter-change')).toBeTruthy();
    expect(wrapper.emitted('filter-change')![0]).toEqual(['role', 'colonel']);
  });

  it('reflects the controlled filter value', () => {
    const active: FilterConfig[] = [{ ...filters[0], value: 'customer' }];
    wrapper = mountBar({ filters: active });
    const select = wrapper.find('#kit-filter-role').element as HTMLSelectElement;
    expect(select.value).toBe('customer');
  });

  it('renders a search box by default and emits update:search on input', async () => {
    wrapper = mountBar();
    const search = wrapper.find('#kit-filter-search');
    expect(search.exists()).toBe(true);
    await search.setValue('alice');
    expect(wrapper.emitted('update:search')).toBeTruthy();
    expect(wrapper.emitted('update:search')![0]).toEqual(['alice']);
  });

  it('hides the search box when showSearch is false', () => {
    wrapper = mountBar({ showSearch: false });
    expect(wrapper.find('#kit-filter-search').exists()).toBe(false);
  });

  it('disables clear when there are no active filters and enables it when there are', async () => {
    wrapper = mountBar({ hasActiveFilters: false });
    const clearBtn = wrapper.findAll('button').find((b) => b.text().includes('clearFilters'));
    expect(clearBtn?.attributes('disabled')).toBeDefined();

    await wrapper.setProps({ hasActiveFilters: true });
    expect(clearBtn?.attributes('disabled')).toBeUndefined();
  });

  it('emits clear when the clear button is activated', async () => {
    wrapper = mountBar({ hasActiveFilters: true });
    const clearBtn = wrapper.findAll('button').find((b) => b.text().includes('clearFilters'));
    await clearBtn!.trigger('click');
    expect(wrapper.emitted('clear')).toBeTruthy();
  });

  it('renders bespoke controls passed via the default slot', () => {
    wrapper = mountBar({}, { default: '<button class="bespoke">Extra</button>' });
    expect(wrapper.find('.bespoke').exists()).toBe(true);
  });

  it('uses a custom searchPlaceholder when provided', () => {
    wrapper = mountBar({ searchPlaceholder: 'Find a customer…' });
    expect(wrapper.find('#kit-filter-search').attributes('placeholder')).toBe('Find a customer…');
  });
});
