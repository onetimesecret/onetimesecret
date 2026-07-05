// src/tests/shared/a11y/CopyButton.a11y.spec.ts

//
// Layer-1 accessibility regression tests for CopyButton.vue — an icon-only
// button that relies on an aria-label for its accessible name.
//

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, vi, afterEach } from 'vitest';
import CopyButton from '@/shared/components/ui/CopyButton.vue';
import { createTestI18n } from '@tests/setup';
import { expectNoA11yViolations } from '@tests/support/axe';

// Stub OIcon as a decorative span (matches the real component's default
// aria-hidden behavior) so the button's accessible name comes from aria-label.
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" aria-hidden="true" />',
    props: ['collection', 'name', 'class'],
  },
}));

const i18n = createTestI18n();

describe('CopyButton a11y', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = (props: Record<string, unknown> = {}) =>
    mount(CopyButton, {
      props: { text: 'secret-to-copy', ...props },
      global: { plugins: [i18n] },
    });

  it('has no a11y violations in the default state', async () => {
    wrapper = mountComponent();
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations with a custom tooltip and testid', async () => {
    wrapper = mountComponent({ tooltip: 'Copy the link', testid: 'copy-link' });
    await expectNoA11yViolations(wrapper);
  });
});
