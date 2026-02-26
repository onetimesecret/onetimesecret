// tests/unit/vue/utils/popupMode.spec.ts

import { describe, expect, it } from 'vitest';
import { getPopupMode } from '@/utils/popupMode';

describe('getPopupMode', () => {
  // BUG: Fails when VITE_POPUP_MODE is set in the environment because
  // getPopupMode(undefined) falls through to import.meta.env.VITE_POPUP_MODE.
  it('returns "none" when raw value is undefined', () => {
    expect(getPopupMode(undefined)).toBe('none');
  });

  it('returns "none" for empty string', () => {
    expect(getPopupMode('')).toBe('none');
  });

  it('returns "none" for invalid values', () => {
    expect(getPopupMode('invalid-value')).toBe('none');
  });

  it('returns "dialog" when set to dialog', () => {
    expect(getPopupMode('dialog')).toBe('dialog');
  });

  it('returns "none" for unrecognized mode like two-step', () => {
    expect(getPopupMode('two-step')).toBe('none');
  });

  it('returns "none" when explicitly set to none', () => {
    expect(getPopupMode('none')).toBe('none');
  });
});
