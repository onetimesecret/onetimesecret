// src/shared/composables/useLogoImage.ts

import type { ImageProps } from '@/schemas/shapes/v3/custom-domain';
import { computed, type MaybeRefOrGetter, toValue } from 'vue';

/**
 * Shared logo-image behavior for the brand editor's two upload entry points:
 * the recipient preview (SecretPreview, click-the-image) and the Simple form
 * (BrandLogoField, an explicit control).
 *
 * Owns the validity check, the base64 -> data-URL derivation, and the
 * file-input change handler (which forwards the picked File and then resets the
 * input so re-picking the same file still re-fires `change`). Keeping this in
 * one place stops the two entry points from diverging.
 */
export function useLogoImage(logoImage: MaybeRefOrGetter<ImageProps | null | undefined>) {
  const isValidLogo = computed(() => {
    const logo = toValue(logoImage);
    return Boolean(logo && typeof logo === 'object' && logo.encoded && logo.content_type);
  });

  const logoSrc = computed(() => {
    if (!isValidLogo.value) return '';
    const logo = toValue(logoImage);
    return `data:${logo?.content_type};base64,${logo?.encoded}`;
  });

  /**
   * Wire onto a file <input>'s @change. Forwards the first picked file to
   * `onUpload`, then clears the input value so selecting the same file again
   * still triggers a fresh change event.
   */
  const onFileChange = (event: Event, onUpload: (file: File) => unknown) => {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) onUpload(file);
    input.value = '';
  };

  return { isValidLogo, logoSrc, onFileChange };
}

/**
 * Read a picked File into a base64 data-URL for local preview — the same shape
 * as `logoSrc` above, so a staged (not-yet-uploaded) image renders through the
 * identical `<img :src>` path as a persisted one. Used by ImageUploadModal to
 * preview before the commit round-trip.
 */
export function fileToDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(reader.error ?? new Error('Failed to read file'));
    reader.readAsDataURL(file);
  });
}
