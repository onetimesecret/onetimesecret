// src/tests/shared/a11y/ExternalLink.a11y.spec.ts

//
// Layer-1 accessibility regression tests for ExternalLink.vue — a link
// primitive that opens in a new tab. The decorative SVG must not leak into
// the link's accessible name, and the link must have discernible text.
//

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, afterEach } from 'vitest';
import ExternalLink from '@/shared/components/common/ExternalLink.vue';
import { expectNoA11yViolations } from '@tests/support/axe';

describe('ExternalLink a11y', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('has no a11y violations with an href and label', async () => {
    wrapper = mount(ExternalLink, {
      props: { href: 'https://example.com/docs', label: 'Documentation' },
    });
    await expectNoA11yViolations(wrapper);
  });
});
