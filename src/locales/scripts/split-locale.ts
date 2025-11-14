#!/usr/bin/env ts-node
/**
 * Locale Migration Script
 *
 * Splits a single locale JSON file into multiple files based on feature domains.
 *
 * Usage:
 *   ts-node split-locale.ts <locale-file> [<locale-file2> ...]
 *
 * Example:
 *   ts-node split-locale.ts src/locales/en.json
 *   ts-node split-locale.ts src/locales/en.json src/locales/fr.json
 *
 * For each input file (e.g., src/locales/en.json), this creates:
 *   - Directory: src/locales/en/
 *   - 16 split files based on feature domains
 *
 * The split preserves the exact JSON structure. Combining the split files
 * will produce an identical JSON object to the original.
 */

import * as fs from 'fs';
import * as path from 'path';

interface LocaleData {
  [key: string]: any;
}

interface FileMappingConfig {
  filename: string;
  description: string;
  keys: string[];
}

/**
 * Defines which top-level keys from web.* go into which output file
 */
const FILE_MAPPINGS: FileMappingConfig[] = [
  {
    filename: 'common.json',
    description: 'COMMON, LABELS, STATUS, FEATURES, UNITS, TITLES',
    keys: ['COMMON', 'LABELS', 'STATUS', 'FEATURES', 'UNITS', 'TITLES']
  },
  {
    filename: 'ui.json',
    description: 'ARIA, INSTRUCTION, validation',
    keys: ['ARIA', 'INSTRUCTION']
  },
  {
    filename: 'layout.json',
    description: 'footer, navigation, site, meta, help',
    keys: ['footer', 'navigation', 'site', 'meta', 'help']
  },
  {
    filename: 'homepage.json',
    description: 'homepage marketing',
    keys: ['homepage']
  },
  {
    filename: 'auth.json',
    description: 'Basic auth: login, signup, forgot, verify',
    keys: ['login', 'signup']
  },
  {
    filename: 'auth-advanced.json',
    description: 'MFA, sessions, recovery codes, WebAuthn, magic links',
    keys: [] // We'll handle auth.* specially
  },
  {
    filename: 'secrets.json',
    description: 'secrets, private, shared',
    keys: ['secrets', 'private', 'shared']
  },
  {
    filename: 'incoming.json',
    description: 'incoming workflow',
    keys: ['incoming']
  },
  {
    filename: 'dashboard.json',
    description: 'dashboard, recent',
    keys: ['dashboard']
  },
  {
    filename: 'account.json',
    description: 'account, settings (profile, security, API, privacy)',
    keys: ['account', 'settings']
  },
  {
    filename: 'regions.json',
    description: 'regions/data sovereignty',
    keys: ['regions']
  },
  {
    filename: 'domains.json',
    description: 'domains',
    keys: ['domains']
  },
  {
    filename: 'teams.json',
    description: 'teams',
    keys: ['teams']
  },
  {
    filename: 'organizations.json',
    description: 'organizations',
    keys: ['organizations']
  },
  {
    filename: 'billing.json',
    description: 'billing, plans, invoices',
    keys: ['billing']
  },
  {
    filename: 'colonel.json',
    description: 'colonel/admin, feedback',
    keys: ['colonel', 'feedback']
  }
];

/**
 * Auth keys that should go into auth.json (basic auth)
 */
const BASIC_AUTH_KEYS = [
  'verify',
  'change-password',
  'close-account',
  'passwordReset',
  'account'
];

/**
 * Auth keys that should go into auth-advanced.json
 */
const ADVANCED_AUTH_KEYS = [
  'mfa',
  'sessions',
  'recovery-codes',
  'webauthn',
  'magicLink',
  'lockout',
  'methods',
  'security',
  'mfa_required',
  'mfa_verification_required',
  'complete_mfa_verification'
];

function ensureDirectoryExists(dirPath: string): void {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
    console.log(`✓ Created directory: ${dirPath}`);
  }
}

function splitAuthObject(authData: any): { basic: any; advanced: any } {
  const basic: any = {};
  const advanced: any = {};

  for (const [key, value] of Object.entries(authData)) {
    if (BASIC_AUTH_KEYS.includes(key)) {
      basic[key] = value;
    } else if (ADVANCED_AUTH_KEYS.includes(key)) {
      advanced[key] = value;
    } else {
      // Default to basic for unknown keys
      console.warn(`⚠ Unknown auth key "${key}" - adding to auth.json`);
      basic[key] = value;
    }
  }

  return { basic, advanced };
}

function extractKeysFromWeb(webData: any, keys: string[]): any {
  const result: any = {};

  for (const key of keys) {
    if (key in webData) {
      result[key] = webData[key];
    }
  }

  return Object.keys(result).length > 0 ? result : null;
}

function splitLocaleFile(inputFilePath: string): void {
  console.log(`\n📄 Processing: ${inputFilePath}`);

  // Read input file
  if (!fs.existsSync(inputFilePath)) {
    console.error(`❌ File not found: ${inputFilePath}`);
    return;
  }

  const inputData: LocaleData = JSON.parse(fs.readFileSync(inputFilePath, 'utf-8'));

  // Create output directory
  const inputDir = path.dirname(inputFilePath);
  const inputBasename = path.basename(inputFilePath, path.extname(inputFilePath));
  const outputDir = path.join(inputDir, inputBasename);

  ensureDirectoryExists(outputDir);

  // Extract all top-level keys except 'web'
  const flatKeys: any = {};
  for (const [key, value] of Object.entries(inputData)) {
    if (key !== 'web') {
      flatKeys[key] = value;
    }
  }

  // Check if we have a 'web' top-level key
  if (!inputData.web) {
    console.error(`❌ Expected 'web' key at top level of ${inputFilePath}`);
    return;
  }

  const webData = inputData.web;
  const processedKeys = new Set<string>();

  // Process each file mapping
  for (const mapping of FILE_MAPPINGS) {
    let fileContent: any = {};

    if (mapping.filename === 'auth.json') {
      // Handle basic auth
      const extractedKeys = extractKeysFromWeb(webData, mapping.keys);
      if (extractedKeys) {
        fileContent = { ...extractedKeys };
      }

      // Add basic auth parts from web.auth
      if (webData.auth) {
        const { basic } = splitAuthObject(webData.auth);
        if (Object.keys(basic).length > 0) {
          fileContent.auth = basic;
        }
      }

      mapping.keys.forEach(k => processedKeys.add(k));

    } else if (mapping.filename === 'auth-advanced.json') {
      // Handle advanced auth
      if (webData.auth) {
        const { advanced } = splitAuthObject(webData.auth);
        if (Object.keys(advanced).length > 0) {
          fileContent.auth = advanced;
        }
      }

    } else {
      // Handle all other files
      const extracted = extractKeysFromWeb(webData, mapping.keys);
      if (extracted) {
        fileContent = extracted;
      }
      mapping.keys.forEach(k => processedKeys.add(k));
    }

    // Build output content with web wrapper
    const outputContent: any = {};

    // Add flat keys to common.json
    if (mapping.filename === 'common.json' && Object.keys(flatKeys).length > 0) {
      Object.assign(outputContent, flatKeys);
    }

    // Add web content
    outputContent.web = fileContent;

    const outputPath = path.join(outputDir, mapping.filename);
    fs.writeFileSync(
      outputPath,
      JSON.stringify(outputContent, null, 2) + '\n',
      'utf-8'
    );

    const totalKeys = countKeys(outputContent);
    console.log(`  ✓ ${mapping.filename.padEnd(25)} (${totalKeys} keys) - ${mapping.description}`);
  }

  // Check for unprocessed keys
  processedKeys.add('auth'); // We handled auth specially
  const unprocessedKeys = Object.keys(webData).filter(k => !processedKeys.has(k));

  if (unprocessedKeys.length > 0) {
    console.warn(`\n⚠ Unprocessed keys found: ${unprocessedKeys.join(', ')}`);
    console.warn(`  These keys were not mapped to any output file.`);
  }

  console.log(`\n✅ Successfully split ${inputFilePath} into ${outputDir}/`);
}

function countKeys(obj: any): number {
  let count = 0;

  function traverse(o: any): void {
    for (const key in o) {
      count++;
      if (typeof o[key] === 'object' && o[key] !== null && !Array.isArray(o[key])) {
        traverse(o[key]);
      }
    }
  }

  traverse(obj);
  return count;
}

/**
 * Recursively sorts object keys for consistent comparison
 */
function sortObjectKeys(obj: any): any {
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
    return obj;
  }

  const sorted: any = {};
  const keys = Object.keys(obj).sort();

  for (const key of keys) {
    sorted[key] = sortObjectKeys(obj[key]);
  }

  return sorted;
}

/**
 * Deep comparison of two objects, ignoring key order
 */
function deepEqual(obj1: any, obj2: any): boolean {
  return JSON.stringify(sortObjectKeys(obj1)) === JSON.stringify(sortObjectKeys(obj2));
}

function verifyReversibility(originalPath: string, splitDir: string): boolean {
  console.log(`\n🔍 Verifying reversibility...`);

  const originalData = JSON.parse(fs.readFileSync(originalPath, 'utf-8'));
  const combinedData: any = { web: {} };

  // Read all split files and combine (exclude debug directory)
  const files = fs.readdirSync(splitDir)
    .filter(f => f.endsWith('.json') && !f.startsWith('_'))
    .sort(); // Sort for consistent ordering

  for (const file of files) {
    const filePath = path.join(splitDir, file);
    const fileData = JSON.parse(fs.readFileSync(filePath, 'utf-8'));

    // Merge all top-level keys except 'web'
    for (const [key, value] of Object.entries(fileData)) {
      if (key !== 'web') {
        combinedData[key] = value;
      }
    }

    if (fileData.web) {
      // Merge web contents
      for (const [key, value] of Object.entries(fileData.web)) {
        if (key === 'auth') {
          // Special handling for auth - merge auth objects
          if (!combinedData.web.auth) {
            combinedData.web.auth = {};
          }
          Object.assign(combinedData.web.auth, value);
        } else {
          combinedData.web[key] = value;
        }
      }
    }
  }

  // Compare using deep equality (ignoring key order)
  if (deepEqual(originalData, combinedData)) {
    console.log(`✅ Verification passed! Split files can be recombined into identical JSON.`);
    console.log(`   (Key order may differ, but all content is preserved)`);
    return true;
  } else {
    console.error(`❌ Verification failed! Combined JSON differs from original.`);

    // Write debug files with sorted keys for easier comparison
    const debugDir = path.join(splitDir, '_debug');
    ensureDirectoryExists(debugDir);
    fs.writeFileSync(
      path.join(debugDir, 'original-sorted.json'),
      JSON.stringify(sortObjectKeys(originalData), null, 2) + '\n'
    );
    fs.writeFileSync(
      path.join(debugDir, 'combined-sorted.json'),
      JSON.stringify(sortObjectKeys(combinedData), null, 2) + '\n'
    );
    console.error(`Debug files written to ${debugDir}/`);
    console.error(`Compare with: diff -u ${debugDir}/original-sorted.json ${debugDir}/combined-sorted.json`);

    return false;
  }
}

// Main execution
function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error(`Usage: ts-node split-locale.ts <locale-file> [<locale-file2> ...]`);
    console.error(`Example: ts-node split-locale.ts src/locales/en.json`);
    process.exit(1);
  }

  console.log('🌍 Locale Migration Script');
  console.log('━'.repeat(60));

  for (const filePath of args) {
    try {
      splitLocaleFile(filePath);

      // Verify
      const inputDir = path.dirname(filePath);
      const inputBasename = path.basename(filePath, path.extname(filePath));
      const outputDir = path.join(inputDir, inputBasename);

      verifyReversibility(filePath, outputDir);

    } catch (error) {
      console.error(`❌ Error processing ${filePath}:`, error);
    }
  }

  console.log('\n━'.repeat(60));
  console.log('✅ Migration complete!');
}

main();
