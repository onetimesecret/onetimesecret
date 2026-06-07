// src/tests/shared/components/billing/PlanCardSkeleton.spec.ts

//
// Structure spec for the PlanCardSkeleton composite (billing plan-card
// archetype, #3269). Asserts the a11y status wrapper, single-parent pulse,
// prop-driven card count (asserted on the .max-w-sm card wrappers so it
// survives geometry tweaks to the feature checklist), and that the pulse class
// lives only on the wrapper, never duplicated on child blocks.
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import PlanCardSkeleton from '@/shared/components/billing/PlanCardSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const cards = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('.max-w-sm');

describe('PlanCardSkeleton', () => {
  it('exposes a busy status region with an sr-only loading label', () => {
    const wrapper = mount(PlanCardSkeleton);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('aria-busy')).toBe('true');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('drives a single pulse from the wrapper with reduced-motion freeze', () => {
    const wrapper = mount(PlanCardSkeleton);
    expect(wrapper.classes()).toContain('animate-pulse');
    expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(1);
  });

  it('renders 2 card skeletons by default', () => {
    const wrapper = mount(PlanCardSkeleton);
    expect(cards(wrapper)).toHaveLength(2);
  });

  it('honours the count prop', () => {
    const wrapper = mount(PlanCardSkeleton, { props: { count: 3 } });
    expect(cards(wrapper)).toHaveLength(3);
  });

  it('mirrors the live grid wrapper geometry', () => {
    const wrapper = mount(PlanCardSkeleton);
    // The outermost wrapper must match PlanSelector's real grid so the
    // load→loaded transition does not jump.
    expect(wrapper.classes()).toContain('max-w-[1600px]');
    expect(wrapper.classes()).toContain('flex-wrap');
    expect(wrapper.classes()).toContain('justify-center');
  });
});
