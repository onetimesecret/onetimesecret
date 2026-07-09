// src/tests/shared/a11y/ButtonGroup.a11y.spec.ts

//
// Layer-1 accessibility regression tests for ButtonGroup.vue — a small
// segmented-button primitive. Each button must have a visible/accessible name.
//

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, afterEach } from 'vitest';
import ButtonGroup from '@/shared/components/ui/ButtonGroup.vue';
import { expectNoA11yViolations } from '@tests/support/axe';

describe('ButtonGroup a11y', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('has no a11y violations when both buttons have labels', async () => {
    wrapper = mount(ButtonGroup, {
      props: { firstVal: 'Left', lastVal: 'Right' },
    });
    await expectNoA11yViolations(wrapper);
  });
});
