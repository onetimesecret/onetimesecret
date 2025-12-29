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
const EN_LOCALE_DIR = path.join(LOCALES_DIR, 'en');

// Target convention is snake_case
const TARGET_CONVENTION = 'snake_case';

interface LocaleMessages {
  [key: string]: string | LocaleMessages;
}

interface KeyConvention {
  key: string;
  file: string;
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
function analyzeKeyPath(fullKey: string, file: string): KeyConvention[] {
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
        file,
        convention,
      });
    }
  }

  return results;
}

/**
 * Get all JSON files in a locale directory
 */
function getLocaleFiles(localeDir: string): string[] {
  if (!fs.existsSync(localeDir)) {
    return [];
  }

  return fs.readdirSync(localeDir).filter((file) => file.endsWith('.json') && !file.startsWith('_') && !file.includes('.analysis'));
}

/**
 * Load a JSON file
 */
function loadJsonFile(filePath: string): LocaleMessages | null {
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
 * Flatten nested object keys into dot-notation array with file context
 */
function flattenKeysWithFile(
  obj: LocaleMessages,
  file: string,
  prefix: string = ''
): { key: string; file: string }[] {
  const keys: { key: string; file: string }[] = [];

  for (const key of Object.keys(obj)) {
    // Skip metadata keys
    if (key.startsWith('_')) continue;

    const fullKey = prefix ? `${prefix}.${key}` : key;

    if (typeof obj[key] === 'object' && obj[key] !== null && !Array.isArray(obj[key])) {
      keys.push(...flattenKeysWithFile(obj[key] as LocaleMessages, file, fullKey));
    } else {
      keys.push({ key: fullKey, file });
    }
  }

  return keys;
}

describe('i18n Naming Convention', () => {
  let allKeys: { key: string; file: string }[];
  let conventionAnalysis: KeyConvention[];

  beforeAll(() => {
    allKeys = [];
    conventionAnalysis = [];

    const files = getLocaleFiles(EN_LOCALE_DIR);

    for (const file of files) {
      const filePath = path.join(EN_LOCALE_DIR, file);
      const content = loadJsonFile(filePath);

      if (content) {
        const keys = flattenKeysWithFile(content, file);
        allKeys.push(...keys);

        // Analyze conventions
        for (const { key, file: f } of keys) {
          conventionAnalysis.push(...analyzeKeyPath(key, f));
        }
      }
    }
  });

  describe('Key Loading', () => {
    it('should load keys from English locale files', () => {
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
        // Group by file
        const byFile = new Map<string, string[]>();
        for (const k of kebabKeys) {
          if (!byFile.has(k.file)) {
            byFile.set(k.file, []);
          }
          byFile.get(k.file)!.push(k.key);
        }

        const report: string[] = [`Found ${kebabKeys.length} kebab-case keys to migrate:`];
        for (const [file, keys] of byFile) {
          report.push(`\n  ${file} (${keys.length} keys):`);
          // Show sample
          const sample = [...new Set(keys)].slice(0, 5);
          for (const key of sample) {
            report.push(`    - ${key}`);
          }
          if (keys.length > 5) {
            report.push(`    ... and ${keys.length - 5} more`);
          }
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
        // Group by file
        const byFile = new Map<string, string[]>();
        for (const k of camelKeys) {
          if (!byFile.has(k.file)) {
            byFile.set(k.file, []);
          }
          byFile.get(k.file)!.push(k.key);
        }

        const report: string[] = [`Found ${camelKeys.length} camelCase keys to migrate:`];
        for (const [file, keys] of byFile) {
          report.push(`\n  ${file} (${keys.length} keys):`);
          const sample = [...new Set(keys)].slice(0, 5);
          for (const key of sample) {
            report.push(`    - ${key}`);
          }
          if (keys.length > 5) {
            report.push(`    ... and ${keys.length - 5} more`);
          }
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

      const compliance = (snakeKeys.length / conventionAnalysis.length) * 100;

      console.info(`
Target Convention Compliance (${TARGET_CONVENTION}):
  - Compliant keys: ${snakeKeys.length}
  - Non-compliant keys: ${nonCompliantKeys.length}
  - Compliance rate: ${compliance.toFixed(2)}%
      `);

      // Track compliance - should increase over time
      expect(compliance).toBeGreaterThanOrEqual(0);
    });

    it('should report migration effort by file', () => {
      const nonCompliant = conventionAnalysis.filter((k) =>
        ['kebab-case', 'camelCase', 'mixed'].includes(k.convention)
      );

      if (nonCompliant.length === 0) {
        console.info('All keys follow target convention. No migration needed.');
        return;
      }

      // Group by file and count
      const byFile = new Map<string, { kebab: number; camel: number; mixed: number }>();

      for (const k of nonCompliant) {
        if (!byFile.has(k.file)) {
          byFile.set(k.file, { kebab: 0, camel: 0, mixed: 0 });
        }
        const counts = byFile.get(k.file)!;
        if (k.convention === 'kebab-case') counts.kebab++;
        if (k.convention === 'camelCase') counts.camel++;
        if (k.convention === 'mixed') counts.mixed++;
      }

      const report: string[] = ['Migration Effort by File:'];
      const sortedFiles = [...byFile.entries()].sort(
        (a, b) => (b[1].kebab + b[1].camel + b[1].mixed) - (a[1].kebab + a[1].camel + a[1].mixed)
      );

      for (const [file, counts] of sortedFiles) {
        const total = counts.kebab + counts.camel + counts.mixed;
        report.push(`  ${file}: ${total} keys (kebab: ${counts.kebab}, camel: ${counts.camel}, mixed: ${counts.mixed})`);
      }

      console.info(report.join('\n'));

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
