// src/tests/apps/admin/kit/KitPagination.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import KitPagination from '@/apps/admin/components/kit/KitPagination.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

function meta(overrides: Partial<Record<string, number>> = {}) {
  return {
    page: 2,
    per_page: 25,
    total_count: 120,
    total_pages: 5,
    ...overrides,
  };
}

describe('KitPagination (re-homed colonel pagination — CONTRACT 5)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  const mountPager = (props: Record<string, unknown> = {}) =>
    mount(KitPagination, {
      props: { pagination: meta(), ...props },
      global: { plugins: [i18n] },
    });

  const navButtons = () => wrapper.findAll('button');
  const prevButton = () => navButtons().find((b) => b.text().includes('previous'));
  const nextButton = () => navButtons().find((b) => b.text().includes('next'));

  it('preserves the emit contract: update:page on next/prev', async () => {
    wrapper = mountPager();
    await nextButton()!.trigger('click');
    expect(wrapper.emitted('update:page')![0]).toEqual([3]);

    await prevButton()!.trigger('click');
    expect(wrapper.emitted('update:page')![1]).toEqual([1]);
  });

  it('preserves the emit contract: update:perPage on select change', async () => {
    wrapper = mountPager();
    await wrapper.find('#kit-per-page-select').setValue('100');
    expect(wrapper.emitted('update:perPage')).toBeTruthy();
    expect(wrapper.emitted('update:perPage')![0]).toEqual([100]);
  });

  it('disables prev on the first page', () => {
    wrapper = mountPager({ pagination: meta({ page: 1 }) });
    expect(prevButton()!.attributes('disabled')).toBeDefined();
    expect(nextButton()!.attributes('disabled')).toBeUndefined();
  });

  it('disables next on the last page', () => {
    wrapper = mountPager({ pagination: meta({ page: 5 }) });
    expect(nextButton()!.attributes('disabled')).toBeDefined();
    expect(prevButton()!.attributes('disabled')).toBeUndefined();
  });

  it('disables both navigation buttons while loading', () => {
    wrapper = mountPager({ loading: true });
    expect(prevButton()!.attributes('disabled')).toBeDefined();
    expect(nextButton()!.attributes('disabled')).toBeDefined();
  });

  it('does not emit when a disabled button is clicked', async () => {
    wrapper = mountPager({ pagination: meta({ page: 1 }) });
    await prevButton()!.trigger('click');
    expect(wrapper.emitted('update:page')).toBeFalsy();
  });

  it('renders the value-echoed per_page as the selected option', () => {
    wrapper = mountPager({ pagination: meta({ per_page: 100 }) });
    const select = wrapper.find('#kit-per-page-select').element as HTMLSelectElement;
    expect(select.value).toBe('100');
  });

  it('accepts a custom perPageOptions list', () => {
    wrapper = mountPager({ perPageOptions: [10, 20] });
    expect(wrapper.findAll('#kit-per-page-select option')).toHaveLength(2);
  });
});
