// src/utils/popupMode.ts

export type PopupMode = 'none' | 'dialog';

const VALID_MODES: readonly PopupMode[] = ['none', 'dialog'];

/**
 * Reads the popup mode from VITE_POPUP_MODE env var.
 * Returns 'none' for undefined or invalid values.
 *
 * @param raw - Override value for testing; when omitted, reads from import.meta.env
 */
export function getPopupMode(raw?: string): PopupMode {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const value = raw ?? (import.meta as any).env?.VITE_POPUP_MODE;
  if (typeof value === 'string' && VALID_MODES.includes(value as PopupMode)) {
    return value as PopupMode;
  }
  return 'none';
}
