// src/tests/shared/components/closet/CardGridSkeleton.spec.ts

//
// Structure spec for the CardGridSkeleton composite (card-grid archetype).
// Asserts the a11y status wrapper, single-parent pulse, the responsive grid
// classes (literal sm:grid-cols-2 — never interpolated, or JIT drops it), and
// the prop-driven card count.
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import CardGridSkeleton from '@/shared/components/closet/CardGridSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('CardGridSkeleton', () => {
  it('exposes a busy status region with an sr-only loading label', () => {
    const wrapper = mount(CardGridSkeleton);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('aria-busy')).toBe('true');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('drives a single pulse from the grid wrapper with reduced-motion freeze', () => {
    const wrapper = mount(CardGridSkeleton);
    expect(wrapper.classes()).toContain('animate-pulse');
    expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(1);
  });

  it('lays the cards out in a responsive grid (literal sm:grid-cols-2)', () => {
    const wrapper = mount(CardGridSkeleton);
    expect(wrapper.classes()).toContain('grid');
    expect(wrapper.classes()).toContain('sm:grid-cols-2');
  });

  it('renders the default 3 cards', () => {
    const wrapper = mount(CardGridSkeleton);
    expect(blocks(wrapper)).toHaveLength(3);
  });

  it('honours the count prop (6 cards)', () => {
    const wrapper = mount(CardGridSkeleton, { props: { count: 6 } });
    expect(blocks(wrapper)).toHaveLength(6);
  });
});
