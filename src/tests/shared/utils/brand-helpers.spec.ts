// src/tests/shared/utils/brand-helpers.spec.ts
//
// Unit tests for brand-helpers.ts - UI utilities for brand settings.
// Verifies CSS class mappings, display names, and icon mappings are complete
// and consistent with the contract values.

import {
  cornerStyleValues,
  fontFamilyValues,
} from '@/schemas/contracts';
import {
  CornerStyle,
  cornerStyleClasses,
  cornerStyleDisplayMap,
  cornerStyleIconMap,
  cornerStyleOptions,
  FontFamily,
  fontDisplayMap,
  fontFamilyClasses,
  fontIconMap,
  fontOptions,
} from '@/shared/utils/brand-helpers';
import { describe, expect, it } from 'vitest';

describe('brand-helpers', () => {
  describe('FontFamily', () => {
    describe('enum-like object', () => {
      it('contains all font family values', () => {
        expect(FontFamily.SANS).toBe('sans');
        expect(FontFamily.SERIF).toBe('serif');
        expect(FontFamily.MONO).toBe('mono');
      });

      it('values match the contract fontFamilyValues', () => {
        const enumValues = Object.values(FontFamily);
        expect(enumValues.sort()).toEqual([...fontFamilyValues].sort());
      });
    });

    describe('fontOptions array', () => {
      it('contains all font family values from contract', () => {
        expect(fontOptions).toEqual(expect.arrayContaining([...fontFamilyValues]));
        expect(fontOptions.length).toBe(fontFamilyValues.length);
      });

      it('is suitable for form select options', () => {
        // Verify it's an array of strings
        fontOptions.forEach((option) => {
          expect(typeof option).toBe('string');
        });
      });
    });
  });

  describe('CornerStyle', () => {
    describe('enum-like object', () => {
      it('contains all corner style values', () => {
        expect(CornerStyle.ROUNDED).toBe('rounded');
        expect(CornerStyle.PILL).toBe('pill');
        expect(CornerStyle.SQUARE).toBe('square');
      });

      it('values match the contract cornerStyleValues', () => {
        const enumValues = Object.values(CornerStyle);
        expect(enumValues.sort()).toEqual([...cornerStyleValues].sort());
      });
    });

    describe('cornerStyleOptions array', () => {
      it('contains all corner style values from contract', () => {
        expect(cornerStyleOptions).toEqual(expect.arrayContaining([...cornerStyleValues]));
        expect(cornerStyleOptions.length).toBe(cornerStyleValues.length);
      });

      it('is suitable for form select options', () => {
        cornerStyleOptions.forEach((option) => {
          expect(typeof option).toBe('string');
        });
      });
    });
  });

  describe('fontFamilyClasses', () => {
    it('maps all FontFamily values to CSS classes', () => {
      // Every contract value should have a mapping
      fontFamilyValues.forEach((font) => {
        expect(fontFamilyClasses[font]).toBeDefined();
        expect(typeof fontFamilyClasses[font]).toBe('string');
      });
    });

    it('maps to valid Tailwind font classes', () => {
      expect(fontFamilyClasses.sans).toBe('font-sans');
      expect(fontFamilyClasses.serif).toBe('font-serif');
      expect(fontFamilyClasses.mono).toBe('font-mono');
    });

    it('has no extra keys beyond contract values', () => {
      const mappedKeys = Object.keys(fontFamilyClasses);
      expect(mappedKeys.sort()).toEqual([...fontFamilyValues].sort());
    });
  });

  describe('cornerStyleClasses', () => {
    it('maps all CornerStyle values to CSS classes', () => {
      cornerStyleValues.forEach((style) => {
        expect(cornerStyleClasses[style]).toBeDefined();
        expect(typeof cornerStyleClasses[style]).toBe('string');
      });
    });

    it('maps to valid Tailwind border-radius classes', () => {
      expect(cornerStyleClasses.rounded).toBe('rounded-md');
      expect(cornerStyleClasses.pill).toBe('rounded-xl');
      expect(cornerStyleClasses.square).toBe('rounded-none');
    });

    it('has no extra keys beyond contract values', () => {
      const mappedKeys = Object.keys(cornerStyleClasses);
      expect(mappedKeys.sort()).toEqual([...cornerStyleValues].sort());
    });
  });

  describe('fontDisplayMap', () => {
    it('maps all FontFamily values to display names', () => {
      fontFamilyValues.forEach((font) => {
        expect(fontDisplayMap[font]).toBeDefined();
        expect(typeof fontDisplayMap[font]).toBe('string');
        // Display names should be human-readable (non-empty)
        expect(fontDisplayMap[font].length).toBeGreaterThan(0);
      });
    });

    it('provides human-readable display names', () => {
      expect(fontDisplayMap.sans).toBe('Sans Serif');
      expect(fontDisplayMap.serif).toBe('Serif');
      expect(fontDisplayMap.mono).toBe('Monospace');
    });

    it('has no extra keys beyond contract values', () => {
      const mappedKeys = Object.keys(fontDisplayMap);
      expect(mappedKeys.sort()).toEqual([...fontFamilyValues].sort());
    });
  });

  describe('cornerStyleDisplayMap', () => {
    it('maps all CornerStyle values to display names', () => {
      cornerStyleValues.forEach((style) => {
        expect(cornerStyleDisplayMap[style]).toBeDefined();
        expect(typeof cornerStyleDisplayMap[style]).toBe('string');
        expect(cornerStyleDisplayMap[style].length).toBeGreaterThan(0);
      });
    });

    it('provides human-readable display names', () => {
      expect(cornerStyleDisplayMap.rounded).toBe('Rounded');
      expect(cornerStyleDisplayMap.pill).toBe('Pill Shape');
      expect(cornerStyleDisplayMap.square).toBe('Square');
    });

    it('has no extra keys beyond contract values', () => {
      const mappedKeys = Object.keys(cornerStyleDisplayMap);
      expect(mappedKeys.sort()).toEqual([...cornerStyleValues].sort());
    });
  });

  describe('fontIconMap', () => {
    it('maps all FontFamily values to icon class names', () => {
      fontFamilyValues.forEach((font) => {
        expect(fontIconMap[font]).toBeDefined();
        expect(typeof fontIconMap[font]).toBe('string');
        expect(fontIconMap[font].length).toBeGreaterThan(0);
      });
    });

    it('provides valid icon class names', () => {
      // Verify icons are from expected icon libraries (ph- for Phosphor, etc.)
      expect(fontIconMap.sans).toBe('ph-text-aa-bold');
      expect(fontIconMap.serif).toBe('ph-text-t-bold');
      expect(fontIconMap.mono).toBe('ph-code');
    });

    it('has no extra keys beyond contract values', () => {
      const mappedKeys = Object.keys(fontIconMap);
      expect(mappedKeys.sort()).toEqual([...fontFamilyValues].sort());
    });
  });

  describe('cornerStyleIconMap', () => {
    it('maps all CornerStyle values to icon class names', () => {
      cornerStyleValues.forEach((style) => {
        expect(cornerStyleIconMap[style]).toBeDefined();
        expect(typeof cornerStyleIconMap[style]).toBe('string');
        expect(cornerStyleIconMap[style].length).toBeGreaterThan(0);
      });
    });

    it('provides valid icon class names', () => {
      // Verify icons are from expected icon libraries (tabler- for Tabler icons)
      expect(cornerStyleIconMap.rounded).toBe('tabler-border-corner-rounded');
      expect(cornerStyleIconMap.pill).toBe('tabler-border-corner-pill');
      expect(cornerStyleIconMap.square).toBe('tabler-border-corner-square');
    });

    it('has no extra keys beyond contract values', () => {
      const mappedKeys = Object.keys(cornerStyleIconMap);
      expect(mappedKeys.sort()).toEqual([...cornerStyleValues].sort());
    });
  });

  describe('type safety', () => {
    it('FontFamily type includes all contract values', () => {
      // TypeScript compile-time check - if this compiles, types are correct
      const testFont: typeof FontFamily.SANS = 'sans';
      const testFont2: typeof FontFamily.SERIF = 'serif';
      const testFont3: typeof FontFamily.MONO = 'mono';

      expect(testFont).toBe('sans');
      expect(testFont2).toBe('serif');
      expect(testFont3).toBe('mono');
    });

    it('CornerStyle type includes all contract values', () => {
      const testStyle: typeof CornerStyle.ROUNDED = 'rounded';
      const testStyle2: typeof CornerStyle.PILL = 'pill';
      const testStyle3: typeof CornerStyle.SQUARE = 'square';

      expect(testStyle).toBe('rounded');
      expect(testStyle2).toBe('pill');
      expect(testStyle3).toBe('square');
    });
  });

  describe('contract synchronization', () => {
    // These tests ensure that if contract values change,
    // the UI helpers are updated accordingly.

    it('fontFamilyClasses stays synchronized with contract', () => {
      const contractCount = fontFamilyValues.length;
      const helperCount = Object.keys(fontFamilyClasses).length;
      expect(helperCount).toBe(contractCount);
    });

    it('cornerStyleClasses stays synchronized with contract', () => {
      const contractCount = cornerStyleValues.length;
      const helperCount = Object.keys(cornerStyleClasses).length;
      expect(helperCount).toBe(contractCount);
    });

    it('all display maps have matching entry counts', () => {
      expect(Object.keys(fontDisplayMap).length).toBe(fontFamilyValues.length);
      expect(Object.keys(cornerStyleDisplayMap).length).toBe(cornerStyleValues.length);
    });

    it('all icon maps have matching entry counts', () => {
      expect(Object.keys(fontIconMap).length).toBe(fontFamilyValues.length);
      expect(Object.keys(cornerStyleIconMap).length).toBe(cornerStyleValues.length);
    });
  });
});
