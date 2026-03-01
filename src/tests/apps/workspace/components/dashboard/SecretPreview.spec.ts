// src/tests/apps/workspace/components/dashboard/SecretPreview.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import SecretPreview from '@/apps/workspace/components/dashboard/SecretPreview.vue';
import type { BrandSettings, ImageProps } from '@/schemas/models';

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

vi.mock('@/apps/secret/components/branded/BaseSecretDisplay.vue', () => ({
  default: {
    name: 'BaseSecretDisplay',
    template: `<div class="base-secret-display">
      <slot name="logo" />
      <slot name="content" />
      <slot name="action-button" />
    </div>`,
    props: ['defaultTitle', 'domainBranding', 'previewI18n', 'isRevealed', 'cornerClass', 'fontClass'],
  },
}));

const baseBranding: BrandSettings = {
  primary_color: '#dc4a22',
  corner_style: 'rounded',
  font_family: 'sans',
  locale: 'en',
  button_text_light: true,
  instructions_pre_reveal: '',
  instructions_post_reveal: '',
};

const mockLogo: ImageProps = {
  encoded: 'base64data',
  content_type: 'image/png',
  filename: 'logo.png',
};

const mockPreviewI18n = {
  t: (key: string) => key,
} as any;

function mountPreview(overrides: Record<string, any> = {}) {
  return mount(SecretPreview, {
    props: {
      domainBranding: baseBranding,
      secretIdentifier: 'abcd',
      previewI18n: mockPreviewI18n,
      ...overrides,
    },
  });
}

describe('SecretPreview', () => {
  describe('with upload handler', () => {
    it('renders file input when onLogoUpload is provided', () => {
      const wrapper = mountPreview({
        onLogoUpload: vi.fn(),
      });
      expect(wrapper.find('#logo-upload').exists()).toBe(true);
    });

    it('sets cursor-pointer on label when onLogoUpload is provided', () => {
      const wrapper = mountPreview({
        onLogoUpload: vi.fn(),
      });
      const label = wrapper.find('label');
      expect(label.classes()).toContain('cursor-pointer');
    });

    it('sets for attribute on label when onLogoUpload is provided', () => {
      const wrapper = mountPreview({
        onLogoUpload: vi.fn(),
      });
      const label = wrapper.find('label');
      expect(label.attributes('for')).toBe('logo-upload');
    });
  });

  describe('without upload handler (read-only)', () => {
    it('does not render file input when onLogoUpload is omitted', () => {
      const wrapper = mountPreview();
      expect(wrapper.find('#logo-upload').exists()).toBe(false);
    });

    it('sets cursor-default on label when onLogoUpload is omitted', () => {
      const wrapper = mountPreview();
      const label = wrapper.find('label');
      expect(label.classes()).toContain('cursor-default');
    });

    it('does not set for attribute when onLogoUpload is omitted', () => {
      const wrapper = mountPreview();
      const label = wrapper.find('label');
      expect(label.attributes('for')).toBeUndefined();
    });
  });

  describe('logo remove controls', () => {
    it('shows remove button when logo exists and onLogoRemove is provided', () => {
      const wrapper = mountPreview({
        logoImage: mockLogo,
        onLogoRemove: vi.fn(),
      });
      const removeOverlay = wrapper.find('[role="group"]');
      expect(removeOverlay.exists()).toBe(true);
    });

    it('hides remove controls when onLogoRemove is omitted', () => {
      const wrapper = mountPreview({
        logoImage: mockLogo,
      });
      const removeOverlay = wrapper.find('[role="group"]');
      expect(removeOverlay.exists()).toBe(false);
    });
  });
});
