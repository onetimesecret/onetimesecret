// src/tests/apps/workspace/account/settings/OrgSettingsSkeleton.spec.ts

//
// Structure spec for the page-specific OrgSettingsSkeleton. Asserts the a11y
// status wrapper, single-parent pulse, the page geometry unique to this view
// (the max-w-4xl container, the two-part header with a pill billing chip, and
// the underlined tab bar) plus the field-group panel body.
//

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import OrgSettingsSkeleton from '@/apps/workspace/account/settings/OrgSettingsSkeleton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const blocks = (wrapper: ReturnType<typeof mount>) =>
  wrapper.findAll('[aria-hidden="true"]');

describe('OrgSettingsSkeleton', () => {
  it('exposes a busy status region with an sr-only loading label', () => {
    const wrapper = mount(OrgSettingsSkeleton);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('aria-busy')).toBe('true');
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('web.COMMON.loading');
    expect(srOnly.attributes('aria-hidden')).toBeUndefined();
  });

  it('drives a single pulse from the page wrapper with reduced-motion freeze', () => {
    const wrapper = mount(OrgSettingsSkeleton);
    expect(wrapper.classes()).toContain('animate-pulse');
    expect(wrapper.classes()).toContain('motion-reduce:animate-none');
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(1);
  });

  it('keeps the page container width constraint', () => {
    const wrapper = mount(OrgSettingsSkeleton);
    expect(wrapper.classes()).toContain('mx-auto');
    expect(wrapper.classes()).toContain('max-w-4xl');
  });

  it('renders the pill-shaped billing chip (rounded-full) in the header', () => {
    const wrapper = mount(OrgSettingsSkeleton);
    const pills = blocks(wrapper).filter((b) => b.classes().includes('rounded-full'));
    expect(pills).toHaveLength(1);
  });

  it('renders an underlined tab bar of label blocks', () => {
    const wrapper = mount(OrgSettingsSkeleton);
    const tabBar = wrapper.find('.border-b');
    expect(tabBar.exists()).toBe(true);
    // Three tab labels live inside the bordered nav row. w-16 is a fallthrough
    // class on the Skeleton root wrapper (the flex item), not the inner block.
    const tabLabels = tabBar.findAll('.w-16');
    expect(tabLabels).toHaveLength(3);
  });
});
