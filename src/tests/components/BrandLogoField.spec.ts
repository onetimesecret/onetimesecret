// src/tests/components/BrandLogoField.spec.ts
//
// The Simple form's logo control — the discoverable, in-form counterpart to the
// click-the-preview-image affordance. It shows the current thumbnail and, on
// click, opens the shared ImageUploadModal (which stages + commits). These guard
// the two thumbnail states and that the trigger opens the modal wired to the
// current logo and the upload/remove handlers.

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import BrandLogoField from '@/apps/workspace/components/dashboard/brand/BrandLogoField.vue';
import ImageUploadModal from '@/shared/components/modals/ImageUploadModal.vue';
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
    // Stub the modal so these tests stay a unit around the field's own wiring.
    global: { stubs: { OIcon: true, ImageUploadModal: true } },
  });
  return { wrapper, onLogoUpload, onLogoRemove };
};

describe('BrandLogoField', () => {
  it('empty state: shows Upload and no thumbnail', () => {
    const { wrapper } = mountField(null);
    expect(wrapper.text()).toContain('web.branding.upload_logo');
    expect(wrapper.text()).not.toContain('web.branding.replace_logo');
    expect(wrapper.find('img').exists()).toBe(false);
  });

  it('filled state: shows the thumbnail data-URL and Replace', () => {
    const { wrapper } = mountField(validLogo);
    const img = wrapper.get('img');
    expect(img.attributes('src')).toBe('data:image/png;base64,QUJD');
    expect(wrapper.text()).toContain('web.branding.replace_logo');
  });

  it('opens the modal, closed by default, when the control is clicked', async () => {
    const { wrapper } = mountField(validLogo);
    const modal = wrapper.findComponent(ImageUploadModal);

    expect(modal.props('isOpen')).toBe(false);
    await wrapper.get('button').trigger('click');
    expect(modal.props('isOpen')).toBe(true);
  });

  it('wires the current logo and the upload/remove handlers into the modal', () => {
    const { wrapper, onLogoUpload, onLogoRemove } = mountField(validLogo);
    const modal = wrapper.findComponent(ImageUploadModal);

    expect(modal.props('currentImage')).toEqual(validLogo);
    expect(modal.props('onSave')).toBe(onLogoUpload);
    expect(modal.props('onRemove')).toBe(onLogoRemove);
  });
});
