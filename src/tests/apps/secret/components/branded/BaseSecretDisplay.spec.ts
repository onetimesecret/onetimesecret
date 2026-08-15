// src/tests/apps/secret/components/branded/BaseSecretDisplay.spec.ts
//
// Guards the "Show More" toggle over the branded instructions text, which used
// to appear and disappear at random on the recipient page:
//   1. The toggle is driven by the paragraph actually overflowing its clamp,
//      not by a line count re-derived from line-height. The derived threshold
//      was a second copy of the clamp that disagreed with the CSS, so the
//      toggle could sit over text that was already fully visible.
//   2. The clamp is this component's own `instructions-clamp` class. It used
//      to be Tailwind's `line-clamp-6`, which two sibling components
//      re-declared at three lines from a *global* style block — so how much
//      text was hidden depended on stylesheet injection order.
//   3. Nothing about the toggle's presence feeds back into the measurement
//      that decides it: the measured paragraph carries no vertical padding of
//      its own, so a toggle appearing cannot grow the element it was measured
//      from.
//   4. A re-measurement while expanded does not retract the toggle — with no
//      clamp in force there is no overflow to read, and the toggle must not
//      vanish out from under the reader.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createTestI18n } from '@tests/setup';
import { nextTick } from 'vue';
import BaseSecretDisplay from '@/apps/secret/components/branded/BaseSecretDisplay.vue';

const i18n = createTestI18n();

const LONG_TEXT =
  'You have received a confidential message. It can only be viewed once, so ' +
  'make sure you are ready to save it somewhere safe before you continue.';

const mountDisplay = (instructions = LONG_TEXT): VueWrapper =>
  mount(BaseSecretDisplay, {
    props: {
      domainBranding: {
        instructions_pre_reveal: instructions,
        primary_color: '#36454F',
        corner_style: 'rounded',
        font_family: 'sans',
      } as never,
      cornerClass: 'rounded-md',
      fontClass: 'font-sans',
      headingClass: 'font-brand',
      defaultTitle: 'You have a message',
    },
    global: { plugins: [i18n], stubs: { OIcon: true } },
  });

/**
 * jsdom performs no layout, so both heights read 0 and nothing ever overflows.
 * Stub the pair the component compares to model a paragraph whose content is
 * taller than its clamped box (or exactly fits it).
 */
const setOverflow = (wrapper: VueWrapper, { content, visible }: { content: number; visible: number }) => {
  const element = wrapper.get('[data-testid="brand-instructions"]').element;
  Object.defineProperty(element, 'scrollHeight', { value: content, configurable: true });
  Object.defineProperty(element, 'clientHeight', { value: visible, configurable: true });
};

/** Drive the resize path the component listens on, then let rAF + nextTick settle. */
const remeasure = async () => {
  window.dispatchEvent(new Event('resize'));
  await new Promise((resolve) => requestAnimationFrame(() => resolve(null)));
  await nextTick();
};

/**
 * The test i18n is pass-through (ADR-014), so labels render as their keys —
 * assert against the key rather than English copy.
 */
const SHOW_MORE = 'web.LABELS.view_toggle.show_more';
const SHOW_LESS = 'web.LABELS.view_toggle.show_less';

const toggle = (wrapper: VueWrapper) => {
  const found = wrapper.find('[data-testid="brand-instructions-toggle"]');
  return found.exists() ? found : undefined;
};

describe('BaseSecretDisplay (branded) instructions toggle', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    // jsdom ships no ResizeObserver, so the component takes its window-resize
    // fallback. Asserting through that path keeps the test honest about the
    // fallback still working.
    expect(typeof ResizeObserver).toBe('undefined');
  });

  afterEach(() => wrapper?.unmount());

  it('offers no toggle when the text fits inside the clamp', async () => {
    wrapper = mountDisplay();
    setOverflow(wrapper, { content: 60, visible: 60 });
    await remeasure();

    expect(toggle(wrapper)).toBeUndefined();
  });

  it('ignores subpixel overflow rather than offering a toggle that hides nothing', async () => {
    wrapper = mountDisplay();
    setOverflow(wrapper, { content: 61, visible: 60 });
    await remeasure();

    expect(toggle(wrapper)).toBeUndefined();
  });

  it('offers a toggle once the text overflows the clamp', async () => {
    wrapper = mountDisplay();
    setOverflow(wrapper, { content: 120, visible: 60 });
    await remeasure();

    expect(toggle(wrapper)?.text()).toBe(SHOW_MORE);
    expect(toggle(wrapper)?.attributes('aria-expanded')).toBe('false');
  });

  it('drops the clamp when expanded and restores it when collapsed', async () => {
    wrapper = mountDisplay();
    setOverflow(wrapper, { content: 120, visible: 60 });
    await remeasure();

    const paragraph = wrapper.get('[data-testid="brand-instructions"]');
    expect(paragraph.classes()).toContain('instructions-clamp');

    await toggle(wrapper)!.trigger('click');
    expect(paragraph.classes()).not.toContain('instructions-clamp');
    expect(toggle(wrapper)?.text()).toBe(SHOW_LESS);
    expect(toggle(wrapper)?.attributes('aria-expanded')).toBe('true');

    await toggle(wrapper)!.trigger('click');
    expect(paragraph.classes()).toContain('instructions-clamp');
  });

  it('keeps the toggle through a re-measurement taken while expanded', async () => {
    wrapper = mountDisplay();
    setOverflow(wrapper, { content: 120, visible: 60 });
    await remeasure();
    await toggle(wrapper)!.trigger('click');

    // Expanded, the element no longer overflows — reading that as "not long"
    // would retract the toggle mid-use.
    setOverflow(wrapper, { content: 120, visible: 120 });
    await remeasure();

    expect(toggle(wrapper)?.text()).toBe(SHOW_LESS);
  });

  it('measures a paragraph that carries no vertical padding of its own', async () => {
    wrapper = mountDisplay();
    setOverflow(wrapper, { content: 120, visible: 60 });
    await remeasure();

    // Padding on the measured element would let the toggle's own presence
    // change the measurement that decides whether to show it.
    const paragraphClasses = wrapper.get('[data-testid="brand-instructions"]').classes();
    expect(paragraphClasses.filter((name) => /^(p|py|pt|pb)-/.test(name))).toEqual([]);
  });

  it('does not rely on a globally redefinable line-clamp utility', async () => {
    wrapper = mountDisplay();
    setOverflow(wrapper, { content: 120, visible: 60 });
    await remeasure();

    const paragraphClasses = wrapper.get('[data-testid="brand-instructions"]').classes();
    expect(paragraphClasses.some((name) => name.startsWith('line-clamp-'))).toBe(false);
  });
});
