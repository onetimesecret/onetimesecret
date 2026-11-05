import {
  clearPendingLocaleUpdate,
  storePendingLocaleUpdate,
  takePendingLocaleUpdate,
} from '@/utils/pendingLocaleUpdate';
import { JSDOM } from 'jsdom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const NOW = 1_800_000_000_000;
const MAX_AGE_MS = 5 * 60_000;
const SELECTION_KEY = 'locale-selection';
const STORAGE_KEY = `${SELECTION_KEY}.pending-update`;

function record() {
  return { id: 'pending-id', locale: 'fr_CA', accountExtid: 'account-123', createdAt: NOW };
}

describe('pending locale update', () => {
  let dom: JSDOM;

  beforeEach(() => {
    // Vitest can expose Node's storage even on window; use a fresh jsdom instance.
    dom = new JSDOM('', { url: 'https://example.com' });
    vi.stubGlobal('sessionStorage', dom.window.sessionStorage);
    sessionStorage.clear();
    vi.spyOn(Date, 'now').mockReturnValue(NOW);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    sessionStorage.clear();
    vi.unstubAllGlobals();
    dom.window.close();
  });

  it.each(['account-123', null])(
    'round trips accountExtid=%s and consumes only once',
    (accountExtid) => {
      expect(sessionStorage).toBeInstanceOf(dom.window.Storage);

      const token = storePendingLocaleUpdate(SELECTION_KEY, 'fr_CA', accountExtid);

      expect(token).not.toBeNull();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBe(token);
      const stored = JSON.parse(token!);
      expect(stored).toEqual({
        id: expect.any(String),
        locale: 'fr_CA',
        accountExtid,
        createdAt: NOW,
      });
      expect(stored.id).not.toBe('');
      expect(takePendingLocaleUpdate(SELECTION_KEY)).toEqual(stored);
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
      expect(takePendingLocaleUpdate(SELECTION_KEY)).toBeNull();
    }
  );

  it('returns null when there is no pending update', () => {
    expect(takePendingLocaleUpdate(SELECTION_KEY)).toBeNull();
  });

  describe('expiry', () => {
    it.each([0, MAX_AGE_MS - 1, MAX_AGE_MS])('accepts a record aged %i ms', (age) => {
      const stored = { ...record(), createdAt: NOW - age };
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(stored));

      expect(takePendingLocaleUpdate(SELECTION_KEY)).toEqual(stored);
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    });

    it.each([
      ['one millisecond past five minutes', NOW - MAX_AGE_MS - 1],
      ['one millisecond in the future', NOW + 1],
    ])('discards and removes a record %s', (_, createdAt) => {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ ...record(), createdAt }));

      expect(takePendingLocaleUpdate(SELECTION_KEY)).toBeNull();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
      expect(takePendingLocaleUpdate(SELECTION_KEY)).toBeNull();
    });
  });

  describe('stored payload validation', () => {
    it.each([
      ['malformed JSON', '{not:json'],
      ['JSON null', 'null'],
      ['JSON array', '[]'],
      ['JSON string', '"fr_CA"'],
      ['JSON number', '123'],
      ['JSON boolean', 'true'],
      ['empty object', '{}'],
      ['non-finite positive timestamp', JSON.stringify(record()).replace(String(NOW), '1e400')],
      ['non-finite negative timestamp', JSON.stringify(record()).replace(String(NOW), '-1e400')],
    ])('discards and removes %s', (_, payload) => {
      sessionStorage.setItem(STORAGE_KEY, payload);

      expect(takePendingLocaleUpdate(SELECTION_KEY)).toBeNull();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    });

    it.each([
      ['missing id', { id: undefined }],
      ['empty id', { id: '' }],
      ['null id', { id: null }],
      ['numeric id', { id: 123 }],
      ['missing locale', { locale: undefined }],
      ['empty locale', { locale: '' }],
      ['null locale', { locale: null }],
      ['numeric locale', { locale: 123 }],
      ['missing accountExtid', { accountExtid: undefined }],
      ['empty accountExtid', { accountExtid: '' }],
      ['numeric accountExtid', { accountExtid: 123 }],
      ['boolean accountExtid', { accountExtid: false }],
      ['array accountExtid', { accountExtid: [] }],
      ['object accountExtid', { accountExtid: {} }],
      ['missing createdAt', { createdAt: undefined }],
      ['string createdAt', { createdAt: String(NOW) }],
      ['null createdAt', { createdAt: null }],
      ['boolean createdAt', { createdAt: true }],
    ])('discards and removes a record with %s', (_, invalidFields) => {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ ...record(), ...invalidFields }));

      expect(takePendingLocaleUpdate(SELECTION_KEY)).toBeNull();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    });
  });

  describe('ownership and storage keys', () => {
    it('does not let an older token clear a newer record, even for the same selection', () => {
      const olderToken = storePendingLocaleUpdate(SELECTION_KEY, 'fr_CA', 'account-123');
      const newerToken = storePendingLocaleUpdate(SELECTION_KEY, 'fr_CA', 'account-123');

      expect(olderToken).not.toBeNull();
      expect(newerToken).not.toBeNull();
      expect(newerToken).not.toBe(olderToken);
      clearPendingLocaleUpdate(SELECTION_KEY, olderToken);
      expect(sessionStorage.getItem(STORAGE_KEY)).toBe(newerToken);

      clearPendingLocaleUpdate(SELECTION_KEY, newerToken);
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    });

    it('does not read or remove storage for a null ownership token', () => {
      const token = storePendingLocaleUpdate(SELECTION_KEY, 'fr_CA', null);
      const getItem = vi.spyOn(dom.window.Storage.prototype, 'getItem');
      const removeItem = vi.spyOn(dom.window.Storage.prototype, 'removeItem');

      clearPendingLocaleUpdate(SELECTION_KEY, null);

      expect(getItem).not.toHaveBeenCalled();
      expect(removeItem).not.toHaveBeenCalled();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBe(token);
    });

    it('clears unconditionally without a token, even when reading storage would throw', () => {
      sessionStorage.setItem(STORAGE_KEY, '{invalid JSON');
      const getItem = vi.spyOn(dom.window.Storage.prototype, 'getItem').mockImplementation(() => {
        throw new DOMException('denied', 'SecurityError');
      });

      expect(() => clearPendingLocaleUpdate(SELECTION_KEY)).not.toThrow();
      expect(getItem).not.toHaveBeenCalled();
      getItem.mockRestore();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    });

    it('isolates custom selection keys and leaves the selection itself untouched', () => {
      const customKey = 'tenant.locale';
      sessionStorage.setItem(customKey, 'en');
      const defaultToken = storePendingLocaleUpdate(SELECTION_KEY, 'de', null);
      const customToken = storePendingLocaleUpdate(customKey, 'fr_CA', 'account-123');

      expect(defaultToken).not.toBeNull();
      expect(customToken).not.toBeNull();
      expect(sessionStorage.getItem(`${customKey}.pending-update`)).toBe(customToken);
      clearPendingLocaleUpdate(customKey, defaultToken);
      expect(sessionStorage.getItem(`${customKey}.pending-update`)).toBe(customToken);
      expect(takePendingLocaleUpdate(customKey)).toEqual(JSON.parse(customToken!));
      expect(sessionStorage.getItem(`${customKey}.pending-update`)).toBeNull();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBe(defaultToken);

      storePendingLocaleUpdate(customKey, 'es', null);
      clearPendingLocaleUpdate(customKey);
      expect(sessionStorage.getItem(`${customKey}.pending-update`)).toBeNull();
      expect(sessionStorage.getItem(customKey)).toBe('en');
      expect(sessionStorage.getItem(STORAGE_KEY)).toBe(defaultToken);
    });
  });

  describe('unavailable browser APIs', () => {
    it('returns null without replacing an existing record when setItem throws', () => {
      const existing = JSON.stringify(record());
      sessionStorage.setItem(STORAGE_KEY, existing);
      const setItem = vi.spyOn(dom.window.Storage.prototype, 'setItem').mockImplementation(() => {
        throw new DOMException('full', 'QuotaExceededError');
      });

      expect(storePendingLocaleUpdate(SELECTION_KEY, 'de', null)).toBeNull();
      expect(setItem).toHaveBeenCalledWith(STORAGE_KEY, expect.any(String));
      expect(sessionStorage.getItem(STORAGE_KEY)).toBe(existing);
    });

    it('returns null on take and safely skips conditional clear when getItem throws', () => {
      const token = storePendingLocaleUpdate(SELECTION_KEY, 'fr_CA', null);
      expect(token).not.toBeNull();
      const getItem = vi.spyOn(dom.window.Storage.prototype, 'getItem').mockImplementation(() => {
        throw new DOMException('denied', 'SecurityError');
      });
      const removeItem = vi.spyOn(dom.window.Storage.prototype, 'removeItem');

      expect(takePendingLocaleUpdate(SELECTION_KEY)).toBeNull();
      expect(() => clearPendingLocaleUpdate(SELECTION_KEY, token)).not.toThrow();
      expect(getItem).toHaveBeenCalledTimes(2);
      expect(removeItem).not.toHaveBeenCalled();
      getItem.mockRestore();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBe(token);
    });

    it('returns null rather than consuming a record that cannot be removed', () => {
      const stored = JSON.stringify(record());
      sessionStorage.setItem(STORAGE_KEY, stored);
      const removeItem = vi
        .spyOn(dom.window.Storage.prototype, 'removeItem')
        .mockImplementation(() => {
          throw new DOMException('denied', 'SecurityError');
        });

      expect(takePendingLocaleUpdate(SELECTION_KEY)).toBeNull();
      expect(removeItem).toHaveBeenCalledWith(STORAGE_KEY);
      expect(sessionStorage.getItem(STORAGE_KEY)).toBe(stored);
    });

    it.each([undefined, JSON.stringify(record())])(
      'safely clears with token=%s when removeItem throws',
      (token) => {
        const stored = JSON.stringify(record());
        sessionStorage.setItem(STORAGE_KEY, stored);
        const removeItem = vi
          .spyOn(dom.window.Storage.prototype, 'removeItem')
          .mockImplementation(() => {
            throw new DOMException('denied', 'SecurityError');
          });

        expect(() => clearPendingLocaleUpdate(SELECTION_KEY, token)).not.toThrow();
        expect(removeItem).toHaveBeenCalledWith(STORAGE_KEY);
        expect(sessionStorage.getItem(STORAGE_KEY)).toBe(stored);
      }
    );

    it.each([undefined, {}])(
      'returns null without writing when crypto is unavailable: %s',
      (crypto) => {
        vi.stubGlobal('crypto', crypto);
        const setItem = vi.spyOn(dom.window.Storage.prototype, 'setItem');

        expect(storePendingLocaleUpdate(SELECTION_KEY, 'fr_CA', null)).toBeNull();
        expect(setItem).not.toHaveBeenCalled();
        expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
      }
    );
  });
});
