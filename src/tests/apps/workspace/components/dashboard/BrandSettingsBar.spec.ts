// src/tests/apps/workspace/components/dashboard/BrandSettingsBar.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import BrandSettingsBar from '@/apps/workspace/components/dashboard/BrandSettingsBar.vue';
import type { BrandSettings } from '@/schemas/models';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name'],
  },
}));

vi.mock('@/shared/components/common/ColorPicker.vue', () => ({
  default: {
    name: 'ColorPicker',
    template: '<input class="color-picker" />',
    props: ['modelValue', 'name', 'label', 'id'],
  },
}));

vi.mock('@/shared/components/common/CycleButton.vue', () => ({
  default: {
    name: 'CycleButton',
    template: '<button class="cycle-button" />',
    props: ['modelValue', 'defaultValue', 'options', 'label', 'displayMap', 'iconMap'],
  },
}));

vi.mock('@/utils/brand-palette', () => ({
  checkBrandContrast: () => ({ passesAALarge: true, ratio: 7.5 }),
}));

const baseBrandSettings: BrandSettings = {
  primary_color: '#dc4a22',
  corner_style: 'rounded',
  font_family: 'sans',
  locale: 'en',
  button_text_light: true,
  instructions_pre_reveal: '',
  instructions_post_reveal: '',
};

const mockPreviewI18n = {
  t: (key: string) => key,
} as any;

function mountBar(overrides: Record<string, any> = {}) {
  return mount(BrandSettingsBar, {
    props: {
      modelValue: baseBrandSettings,
      isLoading: false,
      isInitialized: true,
      previewI18n: mockPreviewI18n,
      hasUnsavedChanges: true,
      ...overrides,
    },
  });
}

describe('BrandSettingsBar', () => {
  describe('disabled state', () => {
    it('hides save button when disabled', () => {
      const wrapper = mountBar({ disabled: true });
      const buttons = wrapper.findAll('button[type="submit"]');
      expect(buttons).toHaveLength(0);
    });

    it('shows save button when not disabled', () => {
      const wrapper = mountBar({ disabled: false });
      const button = wrapper.find('button[type="submit"]');
      expect(button.exists()).toBe(true);
    });

    it('applies pointer-events-none and opacity-60 when disabled', () => {
      const wrapper = mountBar({ disabled: true });
      const leftSection = wrapper.find('.flex.min-w-0.shrink.items-center.gap-4');
      expect(leftSection.classes()).toContain('pointer-events-none');
      expect(leftSection.classes()).toContain('opacity-60');
    });

    it('does not apply disabled classes when not disabled', () => {
      const wrapper = mountBar({ disabled: false });
      const leftSection = wrapper.find('.flex.min-w-0.shrink.items-center.gap-4');
      expect(leftSection.classes()).not.toContain('pointer-events-none');
      expect(leftSection.classes()).not.toContain('opacity-60');
    });
  });

  describe('save button state', () => {
    it('disables save button when loading', () => {
      const wrapper = mountBar({ isLoading: true });
      const button = wrapper.find('button[type="submit"]');
      expect(button.attributes('disabled')).toBeDefined();
    });

    it('disables save button when no unsaved changes', () => {
      const wrapper = mountBar({ hasUnsavedChanges: false });
      const button = wrapper.find('button[type="submit"]');
      expect(button.attributes('disabled')).toBeDefined();
    });
  });
});
