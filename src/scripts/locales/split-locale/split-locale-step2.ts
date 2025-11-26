#!/usr/bin/env ts-node

// src/scripts/locales/split-locale/split-locale-step2.ts
/**
 * Locale Feature Splitter Script (Step 2)
 *
 * Splits web.json files into multiple feature-domain-specific files.
 *
 * Usage:
 *   ts-node split-locale-step2.ts <web-json-file> [<web-json-file2> ...]
 *
 * Example:
 *   ts-node split-locale-step2.ts src/locales/en/web.json
 *   ts-node split-locale-step2.ts src/locales/en/web.json src/locales/fr/web.json
 *
 * For each input file (e.g., src/locales/en/web.json), this creates
 * 16 feature-specific files in the same directory:
 *   - src/locales/en/_common.json
 *   - src/locales/en/auth.json
 *   - etc.
 *
 * This is Step 2 of a two-step process. Run split-locale-step1.ts first
 * to create web.json from the original locale file.
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
    filename: '_common.json',
    description: 'COMMON, LABELS, STATUS, FEATURES, UNITS, TITLES, ARIA, INSTRUCTION',
    keys: ['COMMON', 'LABELS', 'STATUS', 'FEATURES', 'UNITS', 'TITLES', 'ARIA', 'INSTRUCTION'],
  },
  {
    filename: 'layout.json',
    description: 'footer, navigation, site, meta, help',
    keys: ['footer', 'navigation', 'site', 'meta', 'help'],
  },
  {
    filename: 'homepage.json',
    description: 'homepage marketing',
    keys: ['homepage'],
  },
  {
    filename: 'auth.json',
    description: 'Basic auth: login, signup, forgot, verify',
    keys: ['login', 'signup'],
  },
  {
    filename: 'auth-advanced.json',
    description: 'MFA, sessions, recovery codes, WebAuthn, magic links',
    keys: [], // We'll handle auth.* specially
  },
  {
    filename: 'feature-secrets.json',
    description: 'secrets, private, shared',
    keys: ['secrets', 'private', 'shared'],
  },
  {
    filename: 'feature-incoming.json',
    description: 'incoming workflow',
    keys: ['incoming'],
  },
  {
    filename: 'dashboard.json',
    description: 'dashboard, recent',
    keys: ['dashboard'],
  },
  {
    filename: 'account.json',
    description: 'account, settings (profile, security, API, privacy)',
    keys: ['account', 'settings'],
  },
  {
    filename: 'feature-regions.json',
    description: 'regions/data sovereignty',
    keys: ['regions'],
  },
  {
    filename: 'feature-domains.json',
    description: 'domains',
    keys: ['domains'],
  },
  {
    filename: 'feature-teams.json',
    description: 'teams',
    keys: ['teams'],
  },
  {
    filename: 'feature-organizations.json',
    description: 'organizations',
    keys: ['organizations'],
  },
  {
    filename: 'account-billing.json',
    description: 'billing, plans, invoices',
    keys: ['billing'],
  },
  {
    filename: 'colonel.json',
    description: 'colonel/admin, feedback',
    keys: ['colonel', 'feedback'],
  },
];

/**
 * Auth keys that should go into auth.json (basic auth)
 */
const BASIC_AUTH_KEYS = ['verify', 'change-password', 'close-account', 'passwordReset', 'account'];

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
  'complete_mfa_verification',
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

/**
 * Process basic auth file content
 */
function processBasicAuth(
  webData: any,
  mapping: FileMappingConfig,
  processedKeys: Set<string>
): any {
  let fileContent: any = {};

  const extractedKeys = extractKeysFromWeb(webData, mapping.keys);
  if (extractedKeys) {
    fileContent = { ...extractedKeys };
  }

  // Add basic auth parts from web.auth
  if (!webData.auth) {
    mapping.keys.forEach((k) => processedKeys.add(k));
    return fileContent;
  }

  const { basic } = splitAuthObject(webData.auth);
  if (Object.keys(basic).length > 0) {
    fileContent.auth = basic;
  }

  mapping.keys.forEach((k) => processedKeys.add(k));
  return fileContent;
}

/**
 * Process advanced auth file content
 */
function processAdvancedAuth(webData: any): any {
  const fileContent: any = {};

  if (!webData.auth) {
    return fileContent;
  }

  const { advanced } = splitAuthObject(webData.auth);
  if (Object.keys(advanced).length > 0) {
    fileContent.auth = advanced;
  }

  return fileContent;
}

/**
 * Process standard file content
 */
function processStandardFile(
  webData: any,
  mapping: FileMappingConfig,
  processedKeys: Set<string>
): any {
  let fileContent: any = {};

  const extracted = extractKeysFromWeb(webData, mapping.keys);
  if (extracted) {
    fileContent = extracted;
  }

  mapping.keys.forEach((k) => processedKeys.add(k));
  return fileContent;
}

function splitLocaleFile(inputFilePath: string): void {
  console.log(`\n📄 Processing: ${inputFilePath}`);

  // Read input file
  if (!fs.existsSync(inputFilePath)) {
    console.error(`❌ File not found: ${inputFilePath}`);
    return;
  }

  const inputData: LocaleData = JSON.parse(fs.readFileSync(inputFilePath, 'utf-8'));

  // Output to the same directory as the input file
  const outputDir = path.dirname(inputFilePath);

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
      fileContent = processBasicAuth(webData, mapping, processedKeys);
    } else if (mapping.filename === 'auth-advanced.json') {
      // Handle advanced auth
      fileContent = processAdvancedAuth(webData);
    } else {
      // Handle all other files
      fileContent = processStandardFile(webData, mapping, processedKeys);
    }

    // Build output content with web wrapper
    const outputContent: any = {
      web: fileContent,
    };

    const outputPath = path.join(outputDir, mapping.filename);
    fs.writeFileSync(outputPath, JSON.stringify(outputContent, null, 2) + '\n', 'utf-8');

    const totalKeys = countKeys(outputContent);
    console.log(`  ✓ ${mapping.filename.padEnd(25)} (${totalKeys} keys) - ${mapping.description}`);
  }

  // Check for unprocessed keys
  processedKeys.add('auth'); // We handled auth specially
  const unprocessedKeys = Object.keys(webData).filter((k) => !processedKeys.has(k));

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

/**
 * Merge web content from a file into combined data
 */
function mergeWebContent(combinedData: any, webContent: any): void {
  for (const [key, value] of Object.entries(webContent)) {
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

function verifyReversibility(originalPath: string, splitDir: string): boolean {
  console.log(`\n🔍 Verifying reversibility...`);

  const originalData = JSON.parse(fs.readFileSync(originalPath, 'utf-8'));
  const combinedData: any = { web: {} };

  // Read all split files and combine (exclude source files and debug directory)
  const sourceFileName = path.basename(originalPath);
  const files = fs
    .readdirSync(splitDir)
    .filter(
      (f) =>
        // Exclude the original source file (web.json, email.json, uncategorized.json)
        // Exclude directories
        // Include all feature files including _common.json
        f.endsWith('.json') &&
        f !== sourceFileName &&
        f !== '_debug' &&
        !['web.json', 'email.json', 'uncategorized.json'].includes(f)
    )
    .sort(); // Sort for consistent ordering

  for (const file of files) {
    const filePath = path.join(splitDir, file);
    const fileData = JSON.parse(fs.readFileSync(filePath, 'utf-8'));

    if (fileData.web) {
      mergeWebContent(combinedData, fileData.web);
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
      path.join(debugDir, 'step2-original-sorted.json'),
      JSON.stringify(sortObjectKeys(originalData), null, 2) + '\n'
    );
    fs.writeFileSync(
      path.join(debugDir, 'step2-combined-sorted.json'),
      JSON.stringify(sortObjectKeys(combinedData), null, 2) + '\n'
    );
    console.error(`Debug files written to ${debugDir}/`);
    console.error(
      `Compare with: diff -u ${debugDir}/step2-original-sorted.json ${debugDir}/step2-combined-sorted.json`
    );

    return false;
  }
}

// Main execution
function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error(`Usage: ts-node split-locale-step2.ts <web-json-file> [<web-json-file2> ...]`);
    console.error(`Example: ts-node split-locale-step2.ts src/locales/en/web.json`);
    process.exit(1);
  }

  console.log('🌍 Locale Feature Splitter Script (Step 2)');
  console.log('━'.repeat(60));

  for (const filePath of args) {
    try {
      splitLocaleFile(filePath);

      // Verify
      const outputDir = path.dirname(filePath);

      verifyReversibility(filePath, outputDir);
    } catch (error) {
      console.error(`❌ Error processing ${filePath}:`, error);
    }
  }

  console.log('━'.repeat(60));
  console.log('✅ Migration complete!');
}

main();
