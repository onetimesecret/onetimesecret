// src/tests/shared/components/closet/Skeleton.spec.ts

//
// Tests for Skeleton.vue, the foundational loading-placeholder primitive:
// - Default render (single decorative block, fixed gap + color tokens)
// - `count` repeats N blocks
// - `pulse` toggles the animate-pulse + motion-reduce wrapper class
// - width / height / rounded utilities propagate to each block
//
// Skeleton has no i18n/router/store dependencies, so a plain mount with no
// mocks is sufficient.

import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import Skeleton from '@/shared/components/closet/Skeleton.vue';

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('Skeleton', () => {
  describe('default render', () => {
    it('renders a single decorative block', () => {
      const wrapper = mount(Skeleton);
      expect(blocks(wrapper)).toHaveLength(1);
    });

    it('applies the fixed space-y-2 gap on the wrapper', () => {
      const wrapper = mount(Skeleton);
      expect(wrapper.classes()).toContain('space-y-2');
    });

    it('marks blocks as decorative with aria-hidden', () => {
      const wrapper = mount(Skeleton);
      expect(blocks(wrapper)[0].attributes('aria-hidden')).toBe('true');
    });

    it('uses the established skeleton color tokens', () => {
      const wrapper = mount(Skeleton);
      const block = blocks(wrapper)[0];
      expect(block.classes()).toContain('bg-gray-200');
      expect(block.classes()).toContain('dark:bg-gray-700');
    });

    it('applies the default width/height/rounded utilities', () => {
      const wrapper = mount(Skeleton);
      const block = blocks(wrapper)[0];
      expect(block.classes()).toContain('w-full');
      expect(block.classes()).toContain('h-4');
      expect(block.classes()).toContain('rounded');
    });

    it('does not pulse by default', () => {
      const wrapper = mount(Skeleton);
      expect(wrapper.classes()).not.toContain('animate-pulse');
      expect(wrapper.classes()).not.toContain('motion-reduce:animate-none');
    });
  });

  describe('count', () => {
    it('renders N blocks', () => {
      const wrapper = mount(Skeleton, { props: { count: 4 } });
      expect(blocks(wrapper)).toHaveLength(4);
    });

    it('renders a single block when count is 1', () => {
      const wrapper = mount(Skeleton, { props: { count: 1 } });
      expect(blocks(wrapper)).toHaveLength(1);
    });
  });

  describe('pulse', () => {
    it('adds animate-pulse and motion-reduce:animate-none when true', () => {
      const wrapper = mount(Skeleton, { props: { pulse: true } });
      expect(wrapper.classes()).toContain('animate-pulse');
      expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    });

    it('adds neither class when false', () => {
      const wrapper = mount(Skeleton, { props: { pulse: false } });
      expect(wrapper.classes()).not.toContain('animate-pulse');
      expect(wrapper.classes()).not.toContain('motion-reduce:animate-none');
    });
  });

  describe('utility propagation', () => {
    it('propagates width/height/rounded to every block', () => {
      const wrapper = mount(Skeleton, {
        props: {
          width: 'w-2/3',
          height: 'h-6',
          rounded: 'rounded-full',
          count: 3,
        },
      });

      const all = blocks(wrapper);
      expect(all).toHaveLength(3);
      all.forEach((block) => {
        expect(block.classes()).toContain('w-2/3');
        expect(block.classes()).toContain('h-6');
        expect(block.classes()).toContain('rounded-full');
      });
    });
  });
});
