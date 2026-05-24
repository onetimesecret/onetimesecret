// src/tests/shared/components/common/ColorPicker.spec.ts
//
// Tests for ColorPicker emit normalization and accessibility.
//
// Load-bearing regression: vue-color pickers can emit either a string hex
// or a color object (e.g. `{ hex: '#abcdef', rgba: {...} }`). ColorPicker
// must always emit a normalized uppercase hex string on `update:modelValue`
// — never the raw object.

import ColorPicker from '@/shared/components/common/ColorPicker.vue';
import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';
import { createI18n } from 'vue-i18n';

// Stub vue-color pickers so we can drive `update:modelValue` from tests.
// Each picker accepts a modelValue prop and re-emits when we trigger.
vi.mock('vue-color', () => {
  const makePicker = (name: string) => ({
    name,
    props: ['modelValue', 'disableAlpha', 'presetColors', 'palette'],
    emits: ['update:modelValue'],
    template: `<div :data-picker="'${name}'" data-testid="vc-picker"></div>`,
  });
  return {
    ChromePicker: makePicker('ChromePicker'),
    SketchPicker: makePicker('SketchPicker'),
    CompactPicker: makePicker('CompactPicker'),
    tinycolor: (value: string) => ({
      toRgbString: () => `rgb-string(${value})`,
    }),
  };
});

// Mock HoverTooltip so it doesn't interfere with DOM queries
vi.mock('@/shared/components/common/HoverTooltip.vue', () => ({
  default: {
    name: 'HoverTooltip',
    template: '<div class="hover-tooltip"><slot /></div>',
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        branding: {
          color_picker: 'Color Picker',
        },
      },
    },
  },
});

describe('ColorPicker', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = (props: Record<string, unknown> = {}) =>
    mount(ColorPicker, {
      props: {
        name: 'test-color',
        label: 'Test Color',
        modelValue: '#DC4A22',
        ...props,
      },
      global: { plugins: [i18n] },
      attachTo: document.body,
    });

  describe('Parent v-model -> picker reflection', () => {
    it('reflects a string hex passed by the parent in the hex input', () => {
      wrapper = mountComponent({ modelValue: '#ABCDEF' });

      const input = wrapper.find('input[type="text"]');
      expect((input.element as HTMLInputElement).value).toBe('ABCDEF');
    });

    it('updates the input when parent modelValue changes', async () => {
      wrapper = mountComponent({ modelValue: '#111111' });
      await wrapper.setProps({ modelValue: '#222222' });
      await nextTick();

      const input = wrapper.find('input[type="text"]');
      expect((input.element as HTMLInputElement).value).toBe('222222');
    });
  });

  describe('Object emit normalization (regression)', () => {
    it('emits a string hex when the underlying picker emits an object', async () => {
      wrapper = mountComponent({ modelValue: '#000000' });

      // Open the picker so the child component is mounted via Teleport
      await wrapper.find('[role="button"]').trigger('click');
      await nextTick();

      // Find the stubbed picker (mounted to body via Teleport)
      const picker = wrapper.findComponent({ name: 'ChromePicker' });
      expect(picker.exists()).toBe(true);

      // Simulate vue-color emitting an object payload
      picker.vm.$emit('update:modelValue', {
        hex: '#abcdef',
        rgba: { r: 171, g: 205, b: 239, a: 1 },
      });
      await nextTick();

      const emitted = wrapper.emitted('update:modelValue') ?? [];
      // Find the emission after the open action — should be the object handling
      const stringEmits = emitted.filter((args) => typeof args[0] === 'string');
      expect(stringEmits.length).toBeGreaterThan(0);

      // None of the emissions should leak the raw object out to the parent
      const objectLeaks = emitted.filter(
        (args) => typeof args[0] === 'object' && args[0] !== null
      );
      expect(objectLeaks).toHaveLength(0);

      // The normalized value should be an uppercase hex string
      const last = stringEmits[stringEmits.length - 1][0] as string;
      expect(last).toMatch(/^#[0-9A-F]{6}([0-9A-F]{2})?$/);
      expect(last).toBe(last.toUpperCase());
    });
  });

  describe('Idempotent emits', () => {
    it('does not re-emit when internal value converges with parent (case-insensitive)', async () => {
      wrapper = mountComponent({ modelValue: '#abcdef' });
      await nextTick();

      // Reset emitted history
      const before = (wrapper.emitted('update:modelValue') ?? []).length;

      // Parent sends the same hex with different case
      await wrapper.setProps({ modelValue: '#ABCDEF' });
      await nextTick();

      const after = (wrapper.emitted('update:modelValue') ?? []).length;
      expect(after).toBe(before);
    });
  });

  describe('Accessibility (ARIA roles)', () => {
    it('has exactly one element with role="button" (the trigger)', () => {
      wrapper = mountComponent();
      const buttons = wrapper.findAll('[role="button"]');
      expect(buttons).toHaveLength(1);
    });

    it('does not nest the hex input inside a role="button" element', () => {
      wrapper = mountComponent();
      const input = wrapper.find('input[type="text"]').element as HTMLElement;
      expect(input).toBeTruthy();

      // Walk ancestors and ensure none claim role="button"
      let parent: HTMLElement | null = input.parentElement;
      let foundButtonAncestor = false;
      while (parent && parent !== document.body) {
        if (parent.getAttribute('role') === 'button') {
          foundButtonAncestor = true;
          break;
        }
        parent = parent.parentElement;
      }
      expect(foundButtonAncestor).toBe(false);
    });

    it('trigger exposes aria-expanded reflecting open state', async () => {
      wrapper = mountComponent();
      const trigger = wrapper.find('[role="button"]');

      expect(trigger.attributes('aria-expanded')).toBe('false');
      await trigger.trigger('click');
      await nextTick();
      expect(trigger.attributes('aria-expanded')).toBe('true');
    });
  });
});
