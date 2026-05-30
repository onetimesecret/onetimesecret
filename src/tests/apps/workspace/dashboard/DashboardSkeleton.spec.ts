// src/tests/apps/workspace/dashboard/DashboardSkeleton.spec.ts

//
// Layout-regression guard for DashboardSkeleton after composing it from the
// Skeleton primitive. The fragile bits:
// - the container constraints (mx-auto, min/max width) survive,
// - the two `w-1/3` options bars are sized on the flex item (Skeleton root),
//   not on the inner block where they would collapse to a sliver,
// - one parent owns the pulse + reduced-motion freeze.
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import DashboardSkeleton from '@/apps/workspace/dashboard/DashboardSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('DashboardSkeleton', () => {
  it('exposes a busy status region with an sr-only loading label', () => {
    const wrapper = mount(DashboardSkeleton);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('aria-busy')).toBe('true');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('keeps the centered, width-constrained container', () => {
    const wrapper = mount(DashboardSkeleton);
    const cls = (wrapper.element as HTMLElement).className;
    expect(cls).toContain('mx-auto');
    expect(cls).toContain('min-w-[320px]');
    expect(cls).toContain('max-w-2xl');
  });

  it('drives one pulse from the container with reduced-motion freeze', () => {
    const wrapper = mount(DashboardSkeleton);
    expect(wrapper.classes()).toContain('animate-pulse');
    expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(1);
  });

  it('sizes the two options bars on the flex item, not the inner block', () => {
    const wrapper = mount(DashboardSkeleton);
    // w-1/3 must be on a Skeleton root (the flex child), never on an
    // aria-hidden block (that would be 1/3 of a shrink-to-fit wrapper ≈ 0).
    const thirdBlocks = blocks(wrapper).filter((b) =>
      b.classes().includes('w-1/3')
    );
    expect(thirdBlocks).toHaveLength(0);
    const thirdWrappers = wrapper
      .findAll('.w-1\\/3')
      .filter((el) => el.attributes('aria-hidden') !== 'true');
    expect(thirdWrappers).toHaveLength(2);
  });
});
