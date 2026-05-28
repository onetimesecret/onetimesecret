// src/tests/shared/components/closet/TableSkeleton.spec.ts

//
// Layout-regression guard for TableSkeleton after refactoring it to compose
// from the Skeleton primitive. Asserts the geometry the visual reviewer cares
// about: one header row + a 3-row body, the parent owns the pulse (children do
// not double-animate), and rows stay square-cornered (rounded-none).
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import TableSkeleton from '@/shared/components/closet/TableSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('TableSkeleton', () => {
  it('exposes a busy status region with an sr-only loading label', () => {
    const wrapper = mount(TableSkeleton);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('aria-busy')).toBe('true');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    // The label must remain announceable (not aria-hidden).
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('renders a header block plus 3 body rows (4 blocks total)', () => {
    const wrapper = mount(TableSkeleton);
    expect(blocks(wrapper)).toHaveLength(4);
  });

  it('drives the pulse from one parent wrapper with reduced-motion freeze', () => {
    const wrapper = mount(TableSkeleton);
    expect(wrapper.classes()).toContain('animate-pulse');
    expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    // No nested pulse wrappers (children pass :pulse="false").
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(1);
  });

  it('keeps the header rounded-t and the body rows square', () => {
    const wrapper = mount(TableSkeleton);
    const all = blocks(wrapper);
    expect(all[0].classes()).toContain('rounded-t');
    expect(all[1].classes()).toContain('rounded-none');
  });
});
