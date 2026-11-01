// src/tests/shared/utils/aLabelName.spec.ts

import { spellingDiffers, splitALabelName } from '@/shared/utils/aLabelName';
import { describe, expect, it } from 'vitest';

describe('splitALabelName', () => {
  it.each([
    [
      'Unicode subdomain',
      'xn--bcher-kva.example.com',
      'bücher',
      'example.com',
      'xn--bcher-kva',
      'example.com',
    ],
    [
      'Unicode zone',
      'secrets.xn--bcher-kva.de',
      'secrets',
      'bücher.de',
      'secrets',
      'xn--bcher-kva.de',
    ],
    ['ASCII name', 'secrets.example.com', 'secrets', 'example.com', 'secrets', 'example.com'],
    [
      'typed in upper case',
      'secrets.example.com',
      'Secrets',
      'Example.com',
      'secrets',
      'example.com',
    ],
    [
      'multi-label host',
      'a.xn--bcher-kva.example.co.uk',
      'a.bücher',
      'example.co.uk',
      'a.xn--bcher-kva',
      'example.co.uk',
    ],
    ['zone root', 'xn--bcher-kva.de', '', 'bücher.de', '', 'xn--bcher-kva.de'],
    [
      'host already in A-label form',
      'xn--bcher-kva.example.com',
      'xn--bcher-kva',
      'example.com',
      'xn--bcher-kva',
      'example.com',
    ],
  ])('%s', (_label, name, typedHost, typedZone, host, zone) => {
    expect(splitALabelName(name, typedHost, typedZone)).toEqual({ host, zone });
  });

  describe('does not split when the A-label name does not line up with the typed spellings', () => {
    it('more labels than typed (U+3002 is mapped to ".")', () => {
      expect(splitALabelName('xn--bcher-kva.example.com', 'bücher', 'example\u3002com')).toBeNull();
    });

    it('fewer labels than typed', () => {
      expect(splitALabelName('example.com', 'secrets', 'example.com')).toBeNull();
    });

    it('an ASCII label that differs', () => {
      expect(splitALabelName('other.example.com', 'secrets', 'example.com')).toBeNull();
      expect(splitALabelName('secrets.example.org', 'secrets', 'example.com')).toBeNull();
    });

    it('no name or no zone', () => {
      expect(splitALabelName('', 'secrets', 'example.com')).toBeNull();
      expect(splitALabelName('secrets.example.com', 'secrets', '')).toBeNull();
    });
  });
});

describe('spellingDiffers', () => {
  it('differs for a Unicode spelling of the A-label name', () => {
    expect(spellingDiffers('bücher.example.com', 'xn--bcher-kva.example.com')).toBe(true);
  });

  it('does not differ for the same name, in any case', () => {
    expect(spellingDiffers('secrets.example.com', 'secrets.example.com')).toBe(false);
    expect(spellingDiffers('Secrets.Example.com', 'secrets.example.com')).toBe(false);
  });

  it('does not differ when either side is missing', () => {
    expect(spellingDiffers(null, 'example.com')).toBe(false);
    expect(spellingDiffers('bücher.de', undefined)).toBe(false);
    expect(spellingDiffers('', '')).toBe(false);
  });
});
