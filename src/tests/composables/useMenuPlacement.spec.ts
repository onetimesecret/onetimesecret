// src/tests/composables/useMenuPlacement.spec.ts

import {
  BOTTOM_BAR_ATTRIBUTE,
  chooseMenuPlacement,
  useMenuPlacement,
  viewportBottomBoundary,
} from '@/shared/composables/useMenuPlacement';
import { mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, nextTick, ref } from 'vue';

function rect(top: number, height: number): DOMRect {
  return { top, bottom: top + height, height, left: 0, right: 0, width: 0, x: 0, y: top, toJSON: () => ({}) };
}

describe('chooseMenuPlacement', () => {
  it('opens below when the menu fits above the bottom bars', () => {
    expect(chooseMenuPlacement({ top: 100, bottom: 130 }, 200, 600)).toBe('below');
  });

  it('opens above when the bars would cover it and there is more room above', () => {
    expect(chooseMenuPlacement({ top: 480, bottom: 510 }, 200, 600)).toBe('above');
  });

  it('stays below when there is even less room above', () => {
    expect(chooseMenuPlacement({ top: 60, bottom: 90 }, 300, 300)).toBe('below');
  });
});

describe('viewportBottomBoundary', () => {
  beforeEach(() => {
    vi.stubGlobal('innerHeight', 667);
  });
  afterEach(() => {
    document.body.innerHTML = '';
    vi.unstubAllGlobals();
  });

  function bar(position: string, top: number, height: number) {
    const el = document.createElement('nav');
    el.setAttribute(BOTTOM_BAR_ATTRIBUTE, '');
    el.style.position = position;
    el.getBoundingClientRect = () => rect(top, height);
    document.body.appendChild(el);
  }

  it('is the viewport height when no bar is present', () => {
    expect(viewportBottomBoundary()).toBe(667);
  });

  it('is the top of the highest fixed, visible bar', () => {
    bar('fixed', 610, 57);
    expect(viewportBottomBoundary()).toBe(610);
  });

  it('skips a bar in normal flow and a hidden one', () => {
    bar('static', 300, 200);
    bar('fixed', 667, 0);
    expect(viewportBottomBoundary()).toBe(667);
  });
});

describe('useMenuPlacement', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  // A trigger near the bottom of a 667px viewport with a 57px fixed nav,
  // and a 200px menu: it cannot open below without the nav covering it.
  const Harness = defineComponent({
    setup() {
      const trigger = ref<HTMLElement | null>(null);
      const menu = ref<HTMLElement | null>(null);
      const open = ref(false);
      const { placement } = useMenuPlacement(trigger, menu);
      return { trigger, menu, open, placement };
    },
    render() {
      return h('div', [
        h('button', { ref: 'trigger', 'aria-expanded': String(this.open) }),
        this.open ? h('div', { ref: 'menu', 'data-placement': this.placement }) : null,
      ]);
    },
  });

  it('opens above near the bottom bar, and resets when closed', async () => {
    vi.stubGlobal('innerHeight', 667);
    const nav = document.createElement('nav');
    nav.setAttribute(BOTTOM_BAR_ATTRIBUTE, '');
    nav.style.position = 'fixed';
    nav.getBoundingClientRect = () => rect(610, 57);
    document.body.appendChild(nav);

    const offsetHeight = vi
      .spyOn(HTMLElement.prototype, 'offsetHeight', 'get')
      .mockReturnValue(200);
    const wrapper = mount(Harness, { attachTo: document.body });
    (wrapper.vm.trigger as HTMLElement).getBoundingClientRect = () => rect(540, 30);

    wrapper.vm.open = true;
    await vi.waitFor(() => expect(wrapper.vm.placement).toBe('above'));

    wrapper.vm.open = false;
    await vi.waitFor(() => expect(wrapper.vm.placement).toBe('below'));

    await nextTick();
    wrapper.unmount();
    offsetHeight.mockRestore();
    vi.unstubAllGlobals();
  });
});
