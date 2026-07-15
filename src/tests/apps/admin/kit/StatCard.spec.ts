// src/tests/apps/admin/kit/StatCard.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import StatCard from '@/apps/admin/components/kit/StatCard.vue';
import { createTestI18n } from '@tests/setup';

// Minimal RouterLink stub rendering an anchor so we can assert the `to` target
// (StatCard swaps its root to <component :is="'router-link'"> when `to` is set).
const RouterLinkStub = {
  name: 'RouterLink',
  props: ['to'],
  template: '<a class="router-link" :data-to="to"><slot /></a>',
};

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

const i18n = createTestI18n();

describe('StatCard (dashboard metric tile)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  const mountCard = (props: Record<string, unknown> = {}, slots: Record<string, string> = {}) =>
    mount(StatCard, {
      props: { label: 'Total customers', ...props },
      slots,
      global: { plugins: [i18n], stubs: { RouterLink: RouterLinkStub } },
    });

  it('renders the label and value', () => {
    wrapper = mountCard({ value: 1234 });
    expect(wrapper.text()).toContain('Total customers');
    expect(wrapper.text()).toContain('1234');
  });

  it('renders a plain div when no `to` is provided', () => {
    wrapper = mountCard({ value: 1 });
    expect(wrapper.find('.router-link').exists()).toBe(false);
    expect(wrapper.element.tagName).toBe('DIV');
  });

  it('renders a router-link when `to` is provided', () => {
    wrapper = mountCard({ value: 1, to: '/colonel/customers' });
    const link = wrapper.find('.router-link');
    expect(link.exists()).toBe(true);
    expect(link.attributes('data-to')).toBe('/colonel/customers');
  });

  it('renders an icon when `icon` is set', () => {
    wrapper = mountCard({ value: 1, icon: 'users' });
    expect(wrapper.find('.o-icon[data-name="users"]').exists()).toBe(true);
  });

  it('shows a skeleton and hides the value while loading', () => {
    wrapper = mountCard({ value: 42, loading: true });
    // value text should be absent while loading
    expect(wrapper.text()).not.toContain('42');
    // a skeleton block is present
    expect(wrapper.find('.animate-pulse').exists()).toBe(true);
  });

  it('renders a trend with directional styling', () => {
    wrapper = mountCard({ value: 10, trend: '+12%', trendDirection: 'up' });
    const trend = wrapper.findAll('p').find((p) => p.text().includes('+12%'));
    expect(trend).toBeDefined();
    expect(trend!.classes().join(' ')).toContain('text-green');
  });

  it('supports a custom value via default slot', () => {
    wrapper = mountCard({}, { default: '<span class="custom-val">Healthy</span>' });
    expect(wrapper.find('.custom-val').exists()).toBe(true);
  });
});
