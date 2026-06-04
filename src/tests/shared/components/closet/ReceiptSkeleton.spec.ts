// src/tests/shared/components/closet/ReceiptSkeleton.spec.ts

//
// Layout-regression guard for ReceiptSkeleton — the heaviest refactor.
// The load-bearing invariants:
// - the gray-50/gray-800 *panel* backgrounds are preserved (they are containers,
//   not placeholder blocks; normalizing them would make nested blocks vanish),
// - circular avatars stay round and 12-sized,
// - the `w-full` instruction line lands on the flex item (Skeleton root), not on
//   the inner block where w-1/3-style collapse would occur,
// - a single parent owns the pulse + reduced-motion freeze.
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import ReceiptSkeleton from '@/shared/components/closet/ReceiptSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('ReceiptSkeleton', () => {
  it('exposes a busy status region with an sr-only loading label', () => {
    const wrapper = mount(ReceiptSkeleton);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('aria-busy')).toBe('true');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('drives one pulse from the root with reduced-motion freeze', () => {
    const wrapper = mount(ReceiptSkeleton);
    expect(wrapper.classes()).toContain('animate-pulse');
    expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(1);
  });

  it('preserves the two gray-50 container panels (not normalized to blocks)', () => {
    const wrapper = mount(ReceiptSkeleton);
    const panels = wrapper.findAll('section.bg-gray-50');
    expect(panels).toHaveLength(2);
    panels.forEach((p) => expect(p.classes()).toContain('dark:bg-gray-800'));
  });

  it('renders 3 circular avatars at w-12 h-12', () => {
    const wrapper = mount(ReceiptSkeleton);
    const avatars = blocks(wrapper).filter(
      (b) => b.classes().includes('rounded-full') && b.classes().includes('w-12')
    );
    expect(avatars).toHaveLength(3);
    avatars.forEach((a) => expect(a.classes()).toContain('h-12'));
  });

  it('sizes the instruction line via the flex-item wrapper (w-full on Skeleton root)', () => {
    const wrapper = mount(ReceiptSkeleton);
    // The 3 instruction rows are `flex gap-2`; the text line's flex item is the
    // Skeleton root carrying w-full. If w-full had been passed as the `width`
    // prop it would land on the inner block inside a shrink-to-fit wrapper and
    // collapse. Assert at least 3 non-block (wrapper) elements carry w-full.
    const fullWrappers = wrapper
      .findAll('.w-full')
      .filter((el) => el.attributes('aria-hidden') !== 'true');
    expect(fullWrappers.length).toBeGreaterThanOrEqual(3);
  });
});
