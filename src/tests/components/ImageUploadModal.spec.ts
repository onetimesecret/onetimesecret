// src/tests/components/ImageUploadModal.spec.ts
//
// The shared staged image-upload dialog. Nothing persists until the confirm CTA;
// the commit is the caller's onSave/onRemove. These guard the staging lifecycle:
// pick -> preview, client-side validation, confirm -> commit + close, a failed
// commit keeps the dialog open with the file staged, remove staging, and reset
// on reopen.

import { flushPromises, mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';
import ImageUploadModal from '@/shared/components/modals/ImageUploadModal.vue';
import type { ImageProps } from '@/schemas/shapes/v3/custom-domain';

// Echo i18n keys; interpolation params (e.g. {max}) are ignored, so we assert on
// the key alone.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k: string) => k }),
}));

// HeadlessUI portals its dialog out of the wrapper subtree; stub the pieces to
// render inline so we can query them. TransitionRoot honours `show` so isOpen
// toggling still gates rendering the way the real component does.
vi.mock('@headlessui/vue', () => ({
  Dialog: { template: '<div><slot /></div>' },
  DialogPanel: { template: '<div><slot /></div>' },
  DialogTitle: { template: '<h3><slot /></h3>' },
  TransitionRoot: { props: ['show'], template: '<div v-if="show"><slot /></div>' },
  TransitionChild: { template: '<div><slot /></div>' },
}));

// Deterministic staged-preview data-URL (avoids FileReader timing flake).
vi.mock('@/shared/composables/useLogoImage', async (importOriginal) => {
  const actual = (await importOriginal()) as Record<string, unknown>;
  return { ...actual, fileToDataUrl: vi.fn(async () => 'data:image/png;base64,STAGED') };
});

const validLogo = {
  encoded: 'QUJD',
  content_type: 'image/png',
  filename: 'logo.png',
} as ImageProps;

const mountModal = (overrides: Record<string, unknown> = {}) => {
  const onSave = vi.fn().mockResolvedValue(true);
  const onRemove = vi.fn().mockResolvedValue(true);
  const wrapper = mount(ImageUploadModal, {
    props: {
      isOpen: true,
      title: 'Domain logo',
      saveLabel: 'Save logo',
      removeLabel: 'Remove logo',
      currentImage: null,
      onSave,
      onRemove,
      ...overrides,
    },
    global: { stubs: { OIcon: true } },
  });
  return { wrapper, onSave, onRemove };
};

type Wrapper = ReturnType<typeof mountModal>['wrapper'];

const buttonByText = (wrapper: Wrapper, text: string) =>
  wrapper.findAll('button').find((b) => b.text().includes(text));

const pick = async (wrapper: Wrapper, file: File) => {
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', { value: [file], configurable: true });
  await input.trigger('change');
  await flushPromises();
};

describe('ImageUploadModal', () => {
  it('stages a picked image: shows the local preview and enables the CTA', async () => {
    const { wrapper } = mountModal();
    await pick(wrapper, new File(['abc'], 'logo.png', { type: 'image/png' }));

    expect(wrapper.get('img').attributes('src')).toBe('data:image/png;base64,STAGED');
    expect(buttonByText(wrapper, 'Save logo')?.attributes('disabled')).toBeUndefined();
  });

  it('rejects a non-image file with a validation message and stages nothing', async () => {
    const { wrapper } = mountModal();
    await pick(wrapper, new File(['abc'], 'notes.txt', { type: 'text/plain' }));

    expect(wrapper.text()).toContain('web.branding.image_invalid_type');
    expect(wrapper.find('img').exists()).toBe(false);
    expect(buttonByText(wrapper, 'Save logo')?.attributes('disabled')).toBe('');
  });

  it('rejects a file over the size limit', async () => {
    const { wrapper } = mountModal({ maxSizeBytes: 1 });
    await pick(wrapper, new File(['abcdef'], 'logo.png', { type: 'image/png' }));

    expect(wrapper.text()).toContain('web.branding.image_too_large');
    expect(wrapper.find('img').exists()).toBe(false);
  });

  it('commits the staged file via onSave and closes on success', async () => {
    const { wrapper, onSave } = mountModal();
    const file = new File(['abc'], 'logo.png', { type: 'image/png' });
    await pick(wrapper, file);

    await buttonByText(wrapper, 'Save logo')!.trigger('click');
    await flushPromises();

    expect(onSave).toHaveBeenCalledWith(file);
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('keeps the dialog open with the file staged when the commit fails', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined); // wrapped-handler failure signal
    const { wrapper } = mountModal({ onSave });
    await pick(wrapper, new File(['abc'], 'logo.png', { type: 'image/png' }));

    await buttonByText(wrapper, 'Save logo')!.trigger('click');
    await flushPromises();

    expect(onSave).toHaveBeenCalled();
    expect(wrapper.emitted('close')).toBeFalsy();
    expect(wrapper.text()).toContain('web.branding.image_upload_failed');
    // The staged preview survives so the user can retry without re-picking.
    expect(wrapper.get('img').attributes('src')).toBe('data:image/png;base64,STAGED');
  });

  it('stages removal of the current image and commits via onRemove', async () => {
    const { wrapper, onRemove } = mountModal({ currentImage: validLogo });

    // The remove affordance is only offered when a persisted image exists.
    await buttonByText(wrapper, 'Remove logo')!.trigger('click');
    await nextTick();
    expect(wrapper.text()).toContain('web.branding.image_will_be_removed');

    // The CTA now confirms the removal.
    await buttonByText(wrapper, 'Remove logo')!.trigger('click');
    await flushPromises();

    expect(onRemove).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('clears staged state when reopened', async () => {
    const { wrapper } = mountModal();
    await pick(wrapper, new File(['abc'], 'logo.png', { type: 'image/png' }));
    expect(wrapper.find('img').exists()).toBe(true);

    await wrapper.setProps({ isOpen: false });
    await wrapper.setProps({ isOpen: true });
    await flushPromises();

    expect(wrapper.find('img').exists()).toBe(false);
    expect(buttonByText(wrapper, 'Save logo')?.attributes('disabled')).toBe('');
  });

  it('emits close from Cancel', async () => {
    const { wrapper } = mountModal();
    await buttonByText(wrapper, 'web.COMMON.word_cancel')!.trigger('click');
    expect(wrapper.emitted('close')).toBeTruthy();
  });
});
