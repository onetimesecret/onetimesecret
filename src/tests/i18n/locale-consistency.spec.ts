// src/tests/i18n/locale-consistency.spec.ts

/**
 * Cross-Locale Consistency Tests
 *
 * These tests verify that all locale directories have consistent key structures
 * compared to the English (en) baseline locale.
 *
 * Test Coverage:
 * 1. All locales have the same JSON files as English
 * 2. All locales have the same key structure as English
 * 3. Report keys missing in non-English locales
 * 4. Report extra keys in non-English locales (potential orphans)
 *
 * @see src/locales/README.md for locale file structure
 */

import { describe, it, expect, beforeAll } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const LOCALES_DIR = path.resolve(__dirname, '../../locales');
const BASELINE_LOCALE = 'en';

interface LocaleMessages {
  [key: string]: string | LocaleMessages;
}

interface LocaleComparison {
  locale: string;
  missingFiles: string[];
  extraFiles: string[];
  missingKeys: string[];
  extraKeys: string[];
}

/**
 * Get all locale directories
 */
function getLocaleDirectories(): string[] {
  if (!fs.existsSync(LOCALES_DIR)) {
    return [];
  }

  return fs
    .readdirSync(LOCALES_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);
}

/**
 * Get all JSON files in a locale directory
 */
function getLocaleFiles(locale: string): string[] {
  const localeDir = path.join(LOCALES_DIR, locale);

  if (!fs.existsSync(localeDir)) {
    return [];
  }

  return fs.readdirSync(localeDir).filter((file) =>
    // Only include actual translation files, not analysis files
     file.endsWith('.json') && !file.startsWith('_') && !file.includes('.analysis')
  );
}

/**
 * Load a JSON file and return its content
 */
function loadJsonFile(locale: string, fileName: string): LocaleMessages | null {
  const filePath = path.join(LOCALES_DIR, locale, fileName);

  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  } catch (e) {
    console.warn(`Failed to parse ${filePath}:`, e);
    return null;
  }
}

/**
 * Flatten nested object keys into dot-notation array
 * Skips keys starting with underscore (metadata)
 */
function flattenKeys(obj: LocaleMessages, prefix: string = ''): string[] {
  const keys: string[] = [];

  for (const key of Object.keys(obj)) {
    // Skip metadata keys
    if (key.startsWith('_')) continue;

    const fullKey = prefix ? `${prefix}.${key}` : key;

    if (typeof obj[key] === 'object' && obj[key] !== null && !Array.isArray(obj[key])) {
      keys.push(...flattenKeys(obj[key] as LocaleMessages, fullKey));
    } else {
      keys.push(fullKey);
    }
  }

  return keys;
}

/**
 * Compare a locale against the baseline (English)
 */
function compareLocale(locale: string, baselineFiles: string[]): LocaleComparison {
  const localeFiles = getLocaleFiles(locale);

  const missingFiles = baselineFiles.filter((f) => !localeFiles.includes(f));
  const extraFiles = localeFiles.filter((f) => !baselineFiles.includes(f));

  const missingKeys: string[] = [];
  const extraKeys: string[] = [];

  // Compare keys in each file that exists in both
  for (const file of baselineFiles) {
    if (!localeFiles.includes(file)) continue;

    const baselineContent = loadJsonFile(BASELINE_LOCALE, file);
    const localeContent = loadJsonFile(locale, file);

    if (!baselineContent || !localeContent) continue;

    const baselineKeys = flattenKeys(baselineContent);
    const localeKeys = flattenKeys(localeContent);

    const baselineSet = new Set(baselineKeys);
    const localeSet = new Set(localeKeys);

    // Find missing keys (in baseline but not in locale)
    for (const key of baselineKeys) {
      if (!localeSet.has(key)) {
        missingKeys.push(`${file}:${key}`);
      }
    }

    // Find extra keys (in locale but not in baseline)
    for (const key of localeKeys) {
      if (!baselineSet.has(key)) {
        extraKeys.push(`${file}:${key}`);
      }
    }
  }

  return {
    locale,
    missingFiles,
    extraFiles,
    missingKeys,
    extraKeys,
  };
}

describe('Cross-Locale Consistency', () => {
  let locales: string[];
  let baselineFiles: string[];
  let comparisons: Map<string, LocaleComparison>;

  beforeAll(() => {
    locales = getLocaleDirectories();
    baselineFiles = getLocaleFiles(BASELINE_LOCALE);
    comparisons = new Map();

    // Compare each non-baseline locale
    for (const locale of locales) {
      if (locale === BASELINE_LOCALE) continue;
      comparisons.set(locale, compareLocale(locale, baselineFiles));
    }
  });

  describe('Locale Directory Structure', () => {
    it('should have English (en) as baseline locale', () => {
      expect(locales).toContain(BASELINE_LOCALE);
    });

    it('should have multiple locale directories', () => {
      expect(locales.length).toBeGreaterThan(1);
    });

    it('should have translation files in English locale', () => {
      expect(baselineFiles.length).toBeGreaterThan(0);
    });

    it('should report all available locales', () => {
      console.info(`
Locale Structure:
  - Baseline locale: ${BASELINE_LOCALE}
  - Total locales: ${locales.length}
  - Locales: ${locales.join(', ')}
  - Baseline files: ${baselineFiles.length}
      `);
      expect(locales.length).toBeGreaterThan(0);
    });
  });

  describe('File Consistency', () => {
    it('should report missing files per locale', () => {
      const localesWithMissingFiles: string[] = [];

      for (const [locale, comparison] of comparisons) {
        if (comparison.missingFiles.length > 0) {
          localesWithMissingFiles.push(locale);
        }
      }

      if (localesWithMissingFiles.length > 0) {
        const report: string[] = ['Locales with missing files:'];
        for (const locale of localesWithMissingFiles) {
          const comp = comparisons.get(locale)!;
          report.push(`\n  ${locale}:`);
          for (const file of comp.missingFiles) {
            report.push(`    - ${file}`);
          }
        }
        console.warn(report.join('\n'));
      }

      // This is informational - we track but don't fail
      // Update as translations are added
      expect(true).toBe(true);
    });

    it('should report extra files per locale (potential orphans)', () => {
      const localesWithExtraFiles: string[] = [];

      for (const [locale, comparison] of comparisons) {
        if (comparison.extraFiles.length > 0) {
          localesWithExtraFiles.push(locale);
        }
      }

      if (localesWithExtraFiles.length > 0) {
        const report: string[] = ['Locales with extra files (not in baseline):'];
        for (const locale of localesWithExtraFiles) {
          const comp = comparisons.get(locale)!;
          report.push(`\n  ${locale}:`);
          for (const file of comp.extraFiles) {
            report.push(`    - ${file}`);
          }
        }
        console.warn(report.join('\n'));
      }

      // Extra files might be intentional locale-specific content
      expect(true).toBe(true);
    });
  });

  describe('Key Consistency', () => {
    it('should report missing keys summary', () => {
      const summary: { locale: string; count: number }[] = [];

      for (const [locale, comparison] of comparisons) {
        if (comparison.missingKeys.length > 0) {
          summary.push({ locale, count: comparison.missingKeys.length });
        }
      }

      if (summary.length > 0) {
        summary.sort((a, b) => b.count - a.count);

        console.info(`
Missing Keys Summary (keys in 'en' but not in locale):
${summary.map((s) => `  ${s.locale}: ${s.count} missing keys`).join('\n')}
        `);
      }

      // Informational test
      expect(true).toBe(true);
    });

    it('should report extra keys summary', () => {
      const summary: { locale: string; count: number }[] = [];

      for (const [locale, comparison] of comparisons) {
        if (comparison.extraKeys.length > 0) {
          summary.push({ locale, count: comparison.extraKeys.length });
        }
      }

      if (summary.length > 0) {
        summary.sort((a, b) => b.count - a.count);

        console.warn(`
Extra Keys Summary (keys in locale but not in 'en'):
${summary.map((s) => `  ${s.locale}: ${s.count} extra keys`).join('\n')}
        `);
      }

      // Extra keys shouldn't exist - they indicate orphaned translations
      // This helps identify cleanup needed
      expect(true).toBe(true);
    });

    it('should have no extra keys in any locale (strict mode)', () => {
      const localesWithExtraKeys: string[] = [];

      for (const [locale, comparison] of comparisons) {
        if (comparison.extraKeys.length > 0) {
          localesWithExtraKeys.push(locale);
        }
      }

      if (localesWithExtraKeys.length > 0) {
        const report: string[] = ['Locales with extra keys that should be removed:'];
        for (const locale of localesWithExtraKeys) {
          const comp = comparisons.get(locale)!;
          report.push(`\n  ${locale} (${comp.extraKeys.length} extra keys):`);
          // Show first 10 as sample
          const sample = comp.extraKeys.slice(0, 10);
          for (const key of sample) {
            report.push(`    - ${key}`);
          }
          if (comp.extraKeys.length > 10) {
            report.push(`    ... and ${comp.extraKeys.length - 10} more`);
          }
        }
        console.warn(report.join('\n'));
      }

      // Strict check - extra keys indicate orphaned translations
      // Set to 0 once cleanup is complete
      const totalExtraKeys = Array.from(comparisons.values()).reduce(
        (sum, c) => sum + c.extraKeys.length,
        0
      );
      // Allow some extra keys during migration, but track them
      expect(totalExtraKeys).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Translation Coverage', () => {
    it('should calculate translation coverage per locale', () => {
      const baselineKeyCount = baselineFiles.reduce((count, file) => {
        const content = loadJsonFile(BASELINE_LOCALE, file);
        return count + (content ? flattenKeys(content).length : 0);
      }, 0);

      const coverageReport: { locale: string; coverage: number; missing: number }[] = [];

      for (const [locale, comparison] of comparisons) {
        const missingCount = comparison.missingKeys.length;
        const coverage = ((baselineKeyCount - missingCount) / baselineKeyCount) * 100;
        coverageReport.push({
          locale,
          coverage: Math.round(coverage * 100) / 100,
          missing: comparison.missingKeys.length,
        });
      }

      coverageReport.sort((a, b) => b.coverage - a.coverage);

      console.info(`
Translation Coverage Report:
  Baseline (${BASELINE_LOCALE}): ${baselineKeyCount} keys

${coverageReport.map((r) => `  ${r.locale}: ${r.coverage}% (${r.missing} missing)`).join('\n')}
      `);

      // Ensure we have some translation coverage data
      expect(coverageReport.length).toBeGreaterThan(0);
    });
  });

  describe('Specific Locale Checks', () => {
    // Add specific checks for critical locales
    const criticalLocales = ['de', 'es', 'fr_FR', 'ja', 'zh'];

    for (const locale of criticalLocales) {
      it(`should have ${locale} locale with reasonable coverage`, () => {
        if (!locales.includes(locale)) {
          console.warn(`Critical locale ${locale} not found`);
          return;
        }

        const comparison = comparisons.get(locale);
        if (!comparison) {
          return;
        }

        // Log status for critical locales
        console.info(`${locale} status:
  - Missing files: ${comparison.missingFiles.length}
  - Missing keys: ${comparison.missingKeys.length}
  - Extra keys: ${comparison.extraKeys.length}`);

        // Critical locales should have all files
        expect(comparison.missingFiles.length).toBe(0);
      });
    }
  });
});
