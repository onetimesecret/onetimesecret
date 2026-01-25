// src/utils/color-utils.ts

export function shouldUseLightText(hexColor: string): boolean {
  // Remove the # if present
  const color = hexColor.replace('#', '');

  // Convert hex to RGB
  const r = parseInt(color.substring(0, 2), 16);
  const g = parseInt(color.substring(2, 4), 16); // Corrected indices
  const b = parseInt(color.substring(4, 6), 16); // Corrected indices

  // Calculate relative luminance using WCAG formula
  // https://www.w3.org/TR/WCAG20-TECHS/G17.html
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;

  // Use light text if background is dark (luminance < 0.5)
  return luminance < 0.5;
}

export function isColorValue(value: string): boolean {
  return /^#|^rgb\(|^hsl\(/.test(value);
}
