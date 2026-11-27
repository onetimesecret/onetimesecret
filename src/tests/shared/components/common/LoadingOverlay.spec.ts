// src/tests/shared/components/common/LoadingOverlay.spec.ts

import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import LoadingOverlay from '@/shared/components/common/LoadingOverlay.vue';

describe('LoadingOverlay', () => {
  it('renders nothing when hidden', () => {
    const wrapper = mount(LoadingOverlay, { props: { show: false } });
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('covers the viewport above sticky page headers (z-30)', () => {
    const wrapper = mount(LoadingOverlay, { props: { show: true, message: 'Loading' } });
    const overlay = wrapper.get('[role="alert"]');
    // jsdom has no layout, so this pins the classes the stacking order relies on.
    expect(overlay.classes()).toEqual(expect.arrayContaining(['fixed', 'inset-0', 'z-40']));
    expect(overlay.attributes('aria-busy')).toBe('true');
    expect(overlay.attributes('aria-label')).toBe('Loading');
  });
});
