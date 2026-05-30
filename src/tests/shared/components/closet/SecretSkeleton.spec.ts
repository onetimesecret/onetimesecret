// src/tests/shared/components/closet/SecretSkeleton.spec.ts

//
// Layout-regression guard for SecretSkeleton. Verifies the bordered container
// is preserved and static (the pulse lives on an inner wrapper, so the border
// does not animate), and that the 2/3-width heading + two body blocks survive.
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import SecretSkeleton from '@/shared/components/closet/SecretSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('SecretSkeleton', () => {
  it('keeps the bordered, padded container', () => {
    const wrapper = mount(SecretSkeleton);
    const container = wrapper.get('div');
    expect(container.classes()).toContain('rounded-lg');
    expect(container.classes()).toContain('border');
    expect(container.classes()).toContain('p-6');
  });

  it('exposes the busy status region on the static outer container', () => {
    const wrapper = mount(SecretSkeleton);
    // role/aria/sr-only live on the OUTER container (the pulse stays inner so
    // the border does not animate). Query the container directly: leading
    // template comments make wrapper.attributes() unreliable for the root.
    const container = wrapper.get('div');
    expect(container.attributes('role')).toBe('status');
    expect(container.attributes('aria-busy')).toBe('true');
    expect(container.classes()).not.toContain('animate-pulse');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('pulses on an inner wrapper, leaving the border static', () => {
    const wrapper = mount(SecretSkeleton);
    // Outer container is not animated.
    expect(wrapper.classes()).not.toContain('animate-pulse');
    const pulses = wrapper.findAll('.animate-pulse');
    expect(pulses).toHaveLength(1);
    expect(pulses[0].classes()).toContain('motion-reduce:animate-none');
  });

  it('renders the 2/3-width heading plus two body blocks', () => {
    const wrapper = mount(SecretSkeleton);
    const all = blocks(wrapper);
    expect(all).toHaveLength(3);
    // Heading is the only one constrained to two-thirds width.
    const twoThirds = all.filter((b) => b.classes().includes('w-2/3'));
    expect(twoThirds).toHaveLength(1);
  });
});
