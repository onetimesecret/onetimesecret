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
      expect(JURISDICTION_ICONS).toHaveProperty('BR');
      expect(JURISDICTION_ICONS).toHaveProperty('MX');
      expect(JURISDICTION_ICONS).toHaveProperty('AU');
      expect(JURISDICTION_ICONS).toHaveProperty('JP');
      expect(JURISDICTION_ICONS).toHaveProperty('SG');
      expect(JURISDICTION_ICONS).toHaveProperty('APAC');
    });

    it('uses a registered sprite collection for all icons', () => {
      Object.values(JURISDICTION_ICONS).forEach((icon) => {
        expect(['fa6-solid', 'ots']).toContain(icon.collection);
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
        collection: 'ots',
        name: 'earth-european-union',
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
      const ots = (name: string) => ({ collection: 'ots', name });
      expect(getJurisdictionIcon('EU')).toEqual(ots('earth-european-union'));
      expect(getJurisdictionIcon('US')).toEqual(ots('earth-united-states'));
      expect(getJurisdictionIcon('CA')).toEqual(ots('earth-canada'));
      expect(getJurisdictionIcon('UK')).toEqual(ots('earth-united-kingdom'));
      expect(getJurisdictionIcon('NZ')).toEqual(ots('earth-new-zealand'));
      expect(getJurisdictionIcon('BR')).toEqual(ots('earth-brazil'));
      expect(getJurisdictionIcon('MX')).toEqual(ots('earth-mexico'));
      expect(getJurisdictionIcon('AU')).toEqual(ots('earth-australia'));
      expect(getJurisdictionIcon('JP')).toEqual(ots('earth-japan'));
      expect(getJurisdictionIcon('SG')).toEqual(ots('earth-singapore'));
      expect(getJurisdictionIcon('APAC').name).toBe('earth-asia');
    });
  });
});
