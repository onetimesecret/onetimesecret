// src/tests/shared/components/closet/SettingsSkeleton.spec.ts

//
// Structure spec for the general SettingsSkeleton composite (settings-page
// archetype). Asserts the a11y status wrapper, single-parent pulse with
// reduced-motion freeze, prop-driven field-group count, and the form-fields
// fold (heading=false drops the heading block but keeps the groups).
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('SettingsSkeleton', () => {
  it('exposes a busy status region with an sr-only loading label', () => {
    const wrapper = mount(SettingsSkeleton);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('aria-busy')).toBe('true');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('drives a single pulse from the wrapper with reduced-motion freeze', () => {
    const wrapper = mount(SettingsSkeleton);
    expect(wrapper.classes()).toContain('animate-pulse');
    expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    // Children pass :pulse="false" — no nested pulse wrappers.
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(1);
  });

  it('renders heading + default 3 field groups (1 + 3*2 = 7 blocks)', () => {
    const wrapper = mount(SettingsSkeleton);
    expect(blocks(wrapper)).toHaveLength(7);
  });

  it('honours the groups prop (heading + 5 groups = 11 blocks)', () => {
    const wrapper = mount(SettingsSkeleton, { props: { groups: 5 } });
    expect(blocks(wrapper)).toHaveLength(11);
  });

  it('drops the heading when heading=false (form-fields fold)', () => {
    const wrapper = mount(SettingsSkeleton, { props: { heading: false, groups: 3 } });
    // No heading block: just 3 groups * 2 = 6 blocks.
    expect(blocks(wrapper)).toHaveLength(6);
  });
});
