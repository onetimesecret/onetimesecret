import { shouldUseLightText } from '@/utils/color-utils';
import { describe, expect, it } from 'vitest';

describe('shouldUseLightText', () => {
  it('should return true for dark colors', () => {
    expect(shouldUseLightText('#000000')).toBe(true); // Black
    expect(shouldUseLightText('#123456')).toBe(true); // Dark blue
  });

  it('should return false for light colors', () => {
    expect(shouldUseLightText('#FFFFFF')).toBe(false); // White
    expect(shouldUseLightText('#ABCDEF')).toBe(false); // Light blue
  });

  it('should handle invalid hex color values gracefully', () => {
    expect(shouldUseLightText('#ZZZZZZ')).toBe(false); // Invalid hex
    expect(shouldUseLightText('#123')).toBe(false); // Invalid length
  });

  it('should handle boundary cases correctly', () => {
    expect(shouldUseLightText('#808080')).toBe(false); // Gray (boundary case)
  });

  it('does not handle shorthand hex color values', () => {
    expect(shouldUseLightText('#000')).toBe(false); // Black shorthand
    expect(shouldUseLightText('#FFF')).toBe(false); // White shorthand
  });
});
