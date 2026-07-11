// src/tests/components/BrandLogoField.spec.ts
//
// The Simple form's logo control — the discoverable, in-form counterpart to the
// click-the-preview-image affordance. Guards the two states (empty vs. filled),
// that picking a file forwards it to onLogoUpload (and resets the input so the
// same file re-fires change), and that Remove calls onLogoRemove.

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import BrandLogoField from '@/apps/workspace/components/dashboard/brand/BrandLogoField.vue';
import type { ImageProps } from '@/schemas/shapes/v3/custom-domain';

// Echo i18n keys so assertions don't depend on translation content (house
// convention — see SecretPreview.spec.ts / BrandEditor.spec.ts).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k: string) => k }),
}));

const validLogo = {
  encoded: 'QUJD',
  content_type: 'image/png',
  filename: 'logo.png',
} as ImageProps;

const mountField = (logoImage: ImageProps | null) => {
  const onLogoUpload = vi.fn().mockResolvedValue(undefined);
  const onLogoRemove = vi.fn().mockResolvedValue(undefined);
  const wrapper = mount(BrandLogoField, {
    props: { logoImage, onLogoUpload, onLogoRemove },
    global: { stubs: { OIcon: true } },
  });
  return { wrapper, onLogoUpload, onLogoRemove };
};

describe('BrandLogoField', () => {
  it('empty state: shows Upload, no thumbnail, no Remove', () => {
    const { wrapper } = mountField(null);
    expect(wrapper.text()).toContain('web.branding.upload_logo');
    expect(wrapper.text()).not.toContain('web.branding.replace_logo');
    expect(wrapper.find('img').exists()).toBe(false);
    // No Remove button when there's nothing to remove.
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('filled state: shows the thumbnail data-URL, Replace, and Remove', () => {
    const { wrapper } = mountField(validLogo);
    const img = wrapper.get('img');
    expect(img.attributes('src')).toBe('data:image/png;base64,QUJD');
    expect(wrapper.text()).toContain('web.branding.replace_logo');
    expect(wrapper.find('button').exists()).toBe(true);
  });

  it('forwards the picked file to onLogoUpload and resets the input', async () => {
    const { wrapper, onLogoUpload } = mountField(null);
    const file = new File(['ABC'], 'logo.png', { type: 'image/png' });
    const input = wrapper.get('input[type="file"]');
    Object.defineProperty(input.element, 'files', { value: [file], configurable: true });

    await input.trigger('change');

    expect(onLogoUpload).toHaveBeenCalledWith(file);
    // Reset so re-picking the same file still fires change.
    expect((input.element as HTMLInputElement).value).toBe('');
  });

  it('calls onLogoRemove when Remove is clicked', async () => {
    const { wrapper, onLogoRemove } = mountField(validLogo);
    await wrapper.get('button').trigger('click');
    expect(onLogoRemove).toHaveBeenCalledTimes(1);
  });
});
