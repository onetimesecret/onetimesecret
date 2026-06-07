// src/tests/shared/components/closet/ListSkeleton.spec.ts

//
// Structure spec for the ListSkeleton composite (list archetype). Asserts the
// a11y status wrapper, single-parent pulse, prop-driven row count (3 blocks per
// row: primary line + secondary line + trailing action), and that the growing
// text column is sized via flex-1 on the row markup (not the Skeleton width
// prop), per decisions rule 7.
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import ListSkeleton from '@/shared/components/closet/ListSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('ListSkeleton', () => {
  it('exposes a busy status region with an sr-only loading label', () => {
    const wrapper = mount(ListSkeleton);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('aria-busy')).toBe('true');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('drives a single pulse from the wrapper with reduced-motion freeze', () => {
    const wrapper = mount(ListSkeleton);
    expect(wrapper.classes()).toContain('animate-pulse');
    expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(1);
  });

  it('renders the default 3 rows (3 blocks per row = 9 blocks)', () => {
    const wrapper = mount(ListSkeleton);
    expect(blocks(wrapper)).toHaveLength(9);
  });

  it('honours the count prop (5 rows = 15 blocks)', () => {
    const wrapper = mount(ListSkeleton, { props: { count: 5 } });
    expect(blocks(wrapper)).toHaveLength(15);
  });

  it('omits the leading icon block by default (text-led rows)', () => {
    const wrapper = mount(ListSkeleton);
    // No icon → no rounded-full or square leading block; default rows are
    // 3 blocks each (primary + secondary line + trailing action).
    expect(blocks(wrapper)).toHaveLength(9);
  });

  it('adds a leading icon block per row when icon is set (4 blocks/row)', () => {
    const wrapper = mount(ListSkeleton, { props: { count: 3, icon: true } });
    expect(blocks(wrapper)).toHaveLength(12);
  });

  it('sizes and shapes the leading icon block (avatar variant)', () => {
    const wrapper = mount(ListSkeleton, {
      props: { count: 1, icon: true, iconSize: 'w-10', iconRounded: 'rounded-full' },
    });
    const iconBlock = blocks(wrapper).find(
      (b) => b.classes().includes('rounded-full')
    );
    expect(iconBlock).toBeTruthy();
    // iconSize sizes both axes (w-10 → h-10) so the primitive's w-full/h-4
    // defaults do not leak onto the square block.
    expect(iconBlock!.classes()).toContain('w-10');
    expect(iconBlock!.classes()).toContain('h-10');
  });

  it('derives the icon height for every responsive width class', () => {
    // A responsive iconSize like "w-5 md:w-8" must map every width class to a
    // height class (h-5 md:h-8). Replacing only the leading "w-" would leave
    // the height axis as "h-5 md:w-8" — missing md:h-8 — so the block would
    // lose its square aspect ratio at the md breakpoint.
    const wrapper = mount(ListSkeleton, {
      props: { count: 1, icon: true, iconSize: 'w-5 md:w-8' },
    });
    const iconBlock = blocks(wrapper).find((b) => b.classes().includes('w-5'));
    expect(iconBlock).toBeTruthy();
    expect(iconBlock!.classes()).toContain('h-5');
    expect(iconBlock!.classes()).toContain('md:h-8');
  });

  it('sizes the growing text column via flex-1 on the row, not a block', () => {
    const wrapper = mount(ListSkeleton);
    // flex-1 must live on a row wrapper (the flex item), never on an
    // aria-hidden Skeleton block — there it would not stretch the row.
    const flexBlocks = blocks(wrapper).filter((b) => b.classes().includes('flex-1'));
    expect(flexBlocks).toHaveLength(0);
    const flexWrappers = wrapper
      .findAll('.flex-1')
      .filter((el) => el.attributes('aria-hidden') !== 'true');
    expect(flexWrappers).toHaveLength(3);
  });
});
