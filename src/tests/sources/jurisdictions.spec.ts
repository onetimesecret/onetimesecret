// src/tests/sources/jurisdictions.spec.ts

import { describe, it, expect } from 'vitest';
import {
  JURISDICTION_ICONS,
  DEFAULT_JURISDICTION_ICON,
  getJurisdictionIcon,
} from '@/sources/jurisdictions';

describe('jurisdictions', () => {
  describe('JURISDICTION_ICONS', () => {
    it('contains expected jurisdiction identifiers', () => {
      expect(JURISDICTION_ICONS).toHaveProperty('EU');
      expect(JURISDICTION_ICONS).toHaveProperty('US');
      expect(JURISDICTION_ICONS).toHaveProperty('CA');
      expect(JURISDICTION_ICONS).toHaveProperty('UK');
      expect(JURISDICTION_ICONS).toHaveProperty('NZ');
    });

    it('uses fa6-solid collection for all icons', () => {
      Object.values(JURISDICTION_ICONS).forEach((icon) => {
        expect(icon.collection).toBe('fa6-solid');
      });
    });
  });

  describe('DEFAULT_JURISDICTION_ICON', () => {
    it('provides fa6-solid globe as fallback', () => {
      expect(DEFAULT_JURISDICTION_ICON).toEqual({
        collection: 'fa6-solid',
        name: 'globe',
      });
    });
  });

  describe('getJurisdictionIcon', () => {
    it('returns mapped icon for known identifier', () => {
      expect(getJurisdictionIcon('EU')).toEqual({
        collection: 'fa6-solid',
        name: 'earth-europe',
      });
    });

    it('returns default for unknown identifier', () => {
      expect(getJurisdictionIcon('XX')).toEqual(DEFAULT_JURISDICTION_ICON);
    });

    it('handles case insensitivity (lowercase input)', () => {
      expect(getJurisdictionIcon('eu')).toEqual(getJurisdictionIcon('EU'));
    });

    it('handles case insensitivity (mixed case input)', () => {
      expect(getJurisdictionIcon('Eu')).toEqual(getJurisdictionIcon('EU'));
    });

    it('returns correct icon for each known jurisdiction', () => {
      expect(getJurisdictionIcon('US').name).toBe('earth-americas');
      expect(getJurisdictionIcon('CA').name).toBe('earth-americas');
      expect(getJurisdictionIcon('UK').name).toBe('earth-europe');
      expect(getJurisdictionIcon('NZ').name).toBe('earth-oceania');
    });
  });
});
