// src/tests/components/BrandFaviconField.spec.ts
//
// The Simple form's favicon control (#3780) — the upload counterpart to the
// "Refresh favicon" button. Cloned from BrandLogoField, so these mirror
// BrandLogoField.spec.ts: guard the two thumbnail states, the upload/replace
// label toggle, that the trigger opens the shared ImageUploadModal, and that the
// modal is wired with the favicon-specific accept/maxSizeBytes constraints (the
// deliberate divergence from the logo control — .ico is accepted and the size
// ceiling is far below the shared image limit).

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import BrandFaviconField from '@/apps/workspace/components/dashboard/brand/BrandFaviconField.vue';
import ImageUploadModal from '@/shared/components/modals/ImageUploadModal.vue';
import type { ImageProps } from '@/schemas/shapes/v3/custom-domain';

// Echo i18n keys so assertions don't depend on translation content (house
// convention — see BrandLogoField.spec.ts / BrandEditor.spec.ts).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k: string) => k }),
}));

// The favicon-specific upload constraints the field passes into the modal.
// Duplicated here (the component keeps them private) so a drift in either the
// allowlist or the size ceiling trips this test.
const FAVICON_ACCEPT = 'image/png,image/svg+xml,image/x-icon,image/vnd.microsoft.icon,.ico';
const FAVICON_MAX_BYTES = 256 * 1024; // 256KB

const validFavicon = {
  encoded: 'QUJD',
  content_type: 'image/x-icon',
  filename: 'favicon.ico',
} as ImageProps;

const mountField = (faviconImage: ImageProps | null) => {
  const onFaviconUpload = vi.fn().mockResolvedValue(undefined);
  const onFaviconRemove = vi.fn().mockResolvedValue(undefined);
  const wrapper = mount(BrandFaviconField, {
    props: { faviconImage, onFaviconUpload, onFaviconRemove },
    // Stub the modal so these tests stay a unit around the field's own wiring.
    global: { stubs: { OIcon: true, ImageUploadModal: true } },
  });
  return { wrapper, onFaviconUpload, onFaviconRemove };
};

describe('BrandFaviconField', () => {
  it('empty state: shows Upload (not Replace) and no thumbnail', () => {
    const { wrapper } = mountField(null);
    expect(wrapper.text()).toContain('web.branding.upload_favicon');
    expect(wrapper.text()).not.toContain('web.branding.replace_favicon');
    expect(wrapper.find('img').exists()).toBe(false);
  });

  it('filled state: shows the thumbnail data-URL and Replace (not Upload)', () => {
    const { wrapper } = mountField(validFavicon);
    const img = wrapper.get('img');
    expect(img.attributes('src')).toBe('data:image/x-icon;base64,QUJD');
    expect(wrapper.text()).toContain('web.branding.replace_favicon');
    expect(wrapper.text()).not.toContain('web.branding.upload_favicon');
  });

  it('exposes the upload trigger under data-testid="domain-favicon-upload"', () => {
    const { wrapper } = mountField(null);
    const trigger = wrapper.find('[data-testid="domain-favicon-upload"]');
    expect(trigger.exists()).toBe(true);
    // The label lives on this trigger and toggles with the current-icon presence.
    expect(trigger.text()).toContain('web.branding.upload_favicon');
    expect(mountField(validFavicon).wrapper
      .find('[data-testid="domain-favicon-upload"]').text()).toContain('web.branding.replace_favicon');
  });

  it('opens the modal, closed by default, when the trigger is clicked', async () => {
    const { wrapper } = mountField(validFavicon);
    const modal = wrapper.findComponent(ImageUploadModal);

    expect(modal.props('isOpen')).toBe(false);
    await wrapper.get('[data-testid="domain-favicon-upload"]').trigger('click');
    expect(modal.props('isOpen')).toBe(true);
  });

  it('wires the current favicon and the upload/remove handlers into the modal', () => {
    const { wrapper, onFaviconUpload, onFaviconRemove } = mountField(validFavicon);
    const modal = wrapper.findComponent(ImageUploadModal);

    expect(modal.props('currentImage')).toEqual(validFavicon);
    expect(modal.props('onSave')).toBe(onFaviconUpload);
    expect(modal.props('onRemove')).toBe(onFaviconRemove);
  });

  it('passes the favicon-specific accept allowlist and size ceiling into the modal', () => {
    const { wrapper } = mountField(null);
    const modal = wrapper.findComponent(ImageUploadModal);

    // .ico is accepted here (the shared logo allowlist omits it) and the ceiling
    // is 256KB — deliberately far below the shared 2MB image limit.
    expect(modal.props('accept')).toBe(FAVICON_ACCEPT);
    expect(modal.props('maxSizeBytes')).toBe(FAVICON_MAX_BYTES);
  });
});
