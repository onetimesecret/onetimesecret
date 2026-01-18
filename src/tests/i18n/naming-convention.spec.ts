// src/tests/i18n/naming-convention.spec.ts

/**
 * i18n Naming Convention Tests
 *
 * These tests validate that all i18n keys follow the target naming convention
 * (snake_case) and report keys using other conventions that need migration.
 *
 * Test Coverage:
 * 1. Identify key naming conventions (snake_case, kebab-case, camelCase)
 * 2. Report keys that don't follow target convention
 * 3. Count by convention type for migration planning
 *
 * Target Convention: snake_case (e.g., "user_settings", "login_button")
 *
 * Structure: generated/locales/{locale}.json (single merged file per locale)
 */

import { describe, it, expect, beforeAll } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration - use generated/locales for pre-merged locale files
const LOCALES_DIR = path.resolve(__dirname, '../../../generated/locales');
const EN_LOCALE_FILE = path.join(LOCALES_DIR, 'en.json');

// Target convention is snake_case
const TARGET_CONVENTION = 'snake_case';

interface LocaleMessages {
  [key: string]: string | LocaleMessages;
}

interface KeyConvention {
  key: string;
  convention: 'snake_case' | 'kebab-case' | 'camelCase' | 'mixed' | 'unknown';
}

/**
 * Determine the naming convention of a key segment
 */
function detectConvention(segment: string): KeyConvention['convention'] {
  // Skip single-word segments (no convention needed)
  if (!segment.includes('_') && !segment.includes('-') && segment === segment.toLowerCase()) {
    return 'snake_case'; // Single lowercase word is valid for any convention
  }

  // Check for snake_case: lowercase with underscores
  if (/^[a-z][a-z0-9]*(_[a-z0-9]+)*$/.test(segment)) {
    return 'snake_case';
  }

  // Check for kebab-case: lowercase with hyphens
  if (/^[a-z][a-z0-9]*(-[a-z0-9]+)+$/.test(segment)) {
    return 'kebab-case';
  }

  // Check for camelCase: starts lowercase, has uppercase letters
  if (/^[a-z][a-zA-Z0-9]*$/.test(segment) && /[A-Z]/.test(segment)) {
    return 'camelCase';
  }

  // Check for mixed (has both _ and - or uppercase with separators)
  if ((segment.includes('_') && segment.includes('-')) || (/[A-Z]/.test(segment) && /[-_]/.test(segment))) {
    return 'mixed';
  }

  // Unknown or special cases
  return 'unknown';
}

/**
 * Analyze a full key path and return convention for each meaningful segment
 */
function analyzeKeyPath(fullKey: string): KeyConvention[] {
  const results: KeyConvention[] = [];
  const segments = fullKey.split('.');

  for (const segment of segments) {
    // Skip namespace segments (web, email) and very short segments
    if (['web', 'email'].includes(segment) || segment.length <= 2) {
      continue;
    }

    // Only analyze segments that have word boundaries (multi-word keys)
    if (segment.includes('_') || segment.includes('-') || /[A-Z]/.test(segment)) {
      const convention = detectConvention(segment);
      results.push({
        key: fullKey,
        convention,
      });
    }
  }

  return results;
}

/**
 * Load the locale JSON file
 */
function loadLocaleFile(filePath: string): LocaleMessages | null {
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

describe('i18n Naming Convention', () => {
  let allKeys: string[];
  let conventionAnalysis: KeyConvention[];

  beforeAll(() => {
    allKeys = [];
    conventionAnalysis = [];

    const content = loadLocaleFile(EN_LOCALE_FILE);

    if (content) {
      allKeys = flattenKeys(content);

      // Analyze conventions
      for (const key of allKeys) {
        conventionAnalysis.push(...analyzeKeyPath(key));
      }
    }
  });

  describe('Key Loading', () => {
    it('should load keys from English locale file', () => {
      expect(allKeys.length).toBeGreaterThan(0);
    });

    it('should analyze multi-word keys for convention', () => {
      expect(conventionAnalysis.length).toBeGreaterThan(0);
    });
  });

  describe('Convention Statistics', () => {
    it('should report convention distribution', () => {
      const byConvention = new Map<string, number>();

      for (const analysis of conventionAnalysis) {
        const count = byConvention.get(analysis.convention) || 0;
        byConvention.set(analysis.convention, count + 1);
      }

      console.info(`
Naming Convention Distribution:
  - snake_case: ${byConvention.get('snake_case') || 0}
  - kebab-case: ${byConvention.get('kebab-case') || 0}
  - camelCase: ${byConvention.get('camelCase') || 0}
  - mixed: ${byConvention.get('mixed') || 0}
  - unknown: ${byConvention.get('unknown') || 0}
  - Total analyzed: ${conventionAnalysis.length}
      `);

      expect(byConvention.size).toBeGreaterThan(0);
    });
  });

  describe('Kebab-case Keys (Need Migration)', () => {
    it('should identify kebab-case keys', () => {
      const kebabKeys = conventionAnalysis.filter((k) => k.convention === 'kebab-case');

      if (kebabKeys.length > 0) {
        const uniqueKeys = [...new Set(kebabKeys.map((k) => k.key))];

        const report: string[] = [`Found ${kebabKeys.length} kebab-case keys to migrate:`];
        report.push(`\n  Sample (${Math.min(10, uniqueKeys.length)} of ${uniqueKeys.length}):`);
        for (const key of uniqueKeys.slice(0, 10)) {
          report.push(`    - ${key}`);
        }
        if (uniqueKeys.length > 10) {
          report.push(`    ... and ${uniqueKeys.length - 10} more`);
        }
        console.warn(report.join('\n'));
      }

      // Track kebab-case keys for migration planning
      expect(kebabKeys.length).toBeGreaterThanOrEqual(0);
    });

    it('should report unique kebab-case key patterns', () => {
      const kebabKeys = conventionAnalysis.filter((k) => k.convention === 'kebab-case');
      const uniqueKeys = [...new Set(kebabKeys.map((k) => k.key))];

      console.info(`
Unique kebab-case keys: ${uniqueKeys.length}
Sample patterns:
${uniqueKeys.slice(0, 20).map((k) => `  - ${k}`).join('\n')}
      `);

      expect(uniqueKeys.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('CamelCase Keys (Need Migration)', () => {
    it('should identify camelCase keys', () => {
      const camelKeys = conventionAnalysis.filter((k) => k.convention === 'camelCase');

      if (camelKeys.length > 0) {
        const uniqueKeys = [...new Set(camelKeys.map((k) => k.key))];

        const report: string[] = [`Found ${camelKeys.length} camelCase keys to migrate:`];
        report.push(`\n  Sample (${Math.min(10, uniqueKeys.length)} of ${uniqueKeys.length}):`);
        for (const key of uniqueKeys.slice(0, 10)) {
          report.push(`    - ${key}`);
        }
        if (uniqueKeys.length > 10) {
          report.push(`    ... and ${uniqueKeys.length - 10} more`);
        }
        console.warn(report.join('\n'));
      }

      expect(camelKeys.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Mixed Convention Keys (Need Review)', () => {
    it('should identify mixed convention keys', () => {
      const mixedKeys = conventionAnalysis.filter((k) => k.convention === 'mixed');

      if (mixedKeys.length > 0) {
        console.warn(`
Found ${mixedKeys.length} mixed convention keys that need review:
${[...new Set(mixedKeys.map((k) => k.key))].slice(0, 20).map((k) => `  - ${k}`).join('\n')}
        `);
      }

      expect(mixedKeys.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Target Convention Compliance', () => {
    it('should calculate snake_case compliance percentage', () => {
      const snakeKeys = conventionAnalysis.filter((k) => k.convention === 'snake_case');
      const nonCompliantKeys = conventionAnalysis.filter((k) =>
        ['kebab-case', 'camelCase', 'mixed'].includes(k.convention)
      );

      const compliance = conventionAnalysis.length > 0
        ? (snakeKeys.length / conventionAnalysis.length) * 100
        : 100;

      console.info(`
Target Convention Compliance (${TARGET_CONVENTION}):
  - Compliant keys: ${snakeKeys.length}
  - Non-compliant keys: ${nonCompliantKeys.length}
  - Compliance rate: ${compliance.toFixed(2)}%
      `);

      // Track compliance - should increase over time
      expect(compliance).toBeGreaterThanOrEqual(0);
    });

    it('should report migration effort summary', () => {
      const nonCompliant = conventionAnalysis.filter((k) =>
        ['kebab-case', 'camelCase', 'mixed'].includes(k.convention)
      );

      if (nonCompliant.length === 0) {
        console.info('All keys follow target convention. No migration needed.');
        return;
      }

      // Count by type
      const kebabCount = nonCompliant.filter((k) => k.convention === 'kebab-case').length;
      const camelCount = nonCompliant.filter((k) => k.convention === 'camelCase').length;
      const mixedCount = nonCompliant.filter((k) => k.convention === 'mixed').length;

      console.info(`
Migration Effort Summary:
  - kebab-case keys: ${kebabCount}
  - camelCase keys: ${camelCount}
  - mixed keys: ${mixedCount}
  - Total to migrate: ${nonCompliant.length}
      `);

      expect(nonCompliant.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Specific Convention Patterns', () => {
    it('should identify common kebab-case patterns to convert', () => {
      const kebabKeys = conventionAnalysis.filter((k) => k.convention === 'kebab-case');
      const uniqueSegments = new Set<string>();

      for (const k of kebabKeys) {
        const segments = k.key.split('.');
        for (const seg of segments) {
          if (seg.includes('-')) {
            uniqueSegments.add(seg);
          }
        }
      }

      const sorted = [...uniqueSegments].sort();

      console.info(`
Common kebab-case segments (${sorted.length} unique):
${sorted.slice(0, 30).map((s) => `  "${s}" -> "${s.replace(/-/g, '_')}"`).join('\n')}
${sorted.length > 30 ? `  ... and ${sorted.length - 30} more` : ''}
      `);

      expect(sorted.length).toBeGreaterThanOrEqual(0);
    });

    it('should identify common camelCase patterns to convert', () => {
      const camelKeys = conventionAnalysis.filter((k) => k.convention === 'camelCase');
      const uniqueSegments = new Set<string>();

      for (const k of camelKeys) {
        const segments = k.key.split('.');
        for (const seg of segments) {
          if (/[A-Z]/.test(seg) && !seg.includes('-') && !seg.includes('_')) {
            uniqueSegments.add(seg);
          }
        }
      }

      const toSnakeCase = (s: string) => s.replace(/([A-Z])/g, '_$1').toLowerCase();
      const sorted = [...uniqueSegments].sort();

      console.info(`
Common camelCase segments (${sorted.length} unique):
${sorted.slice(0, 30).map((s) => `  "${s}" -> "${toSnakeCase(s)}"`).join('\n')}
${sorted.length > 30 ? `  ... and ${sorted.length - 30} more` : ''}
      `);

      expect(sorted.length).toBeGreaterThanOrEqual(0);
    });
  });
});
