#!/usr/bin/env ts-node

// src/scripts/locales/split-locale/split-locale-step1.ts

/**
 * Locale Pre-processor Script (Step 1)
 *
 * Splits locale files by top-level structure into web, email, and uncategorized files.
 *
 * Usage:
 *   ts-node split-locale-step1.ts <locale-file> [<locale-file2> ...]
 *
 * Example:
 *   ts-node split-locale-step1.ts src/locales/en.json
 *   ts-node split-locale-step1.ts src/locales/en.json src/locales/fr.json
 *
 * For each input file (e.g., src/locales/en.json), this creates:
 *   - Directory: src/locales/en/
 *   - 3 files: web.json, email.json, uncategorized.json
 *
 * This is Step 1 of a two-step process. After running this, use
 * split-locale-step2.ts to further split web.json by feature domains.
 */

import * as fs from 'fs';
import * as path from 'path';

interface LocaleData {
  [key: string]: any;
}

function ensureDirectoryExists(dirPath: string): void {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
    console.log(`✓ Created directory: ${dirPath}`);
  }
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

function splitByTopLevelStructure(inputFilePath: string): void {
  console.log(`\n📄 Processing: ${inputFilePath}`);

  // Read input file
  if (!fs.existsSync(inputFilePath)) {
    console.error(`❌ File not found: ${inputFilePath}`);
    return;
  }

  const inputData: LocaleData = JSON.parse(fs.readFileSync(inputFilePath, 'utf-8'));

  // Create output directory using basename
  const inputDir = path.dirname(inputFilePath);
  const inputBasename = path.basename(inputFilePath, path.extname(inputFilePath));
  const outputDir = path.join(inputDir, inputBasename);

  ensureDirectoryExists(outputDir);

  // Separate into three categories
  const webContent: any = {};
  const emailContent: any = {};
  const uncategorizedContent: any = {};

  for (const [key, value] of Object.entries(inputData)) {
    if (key === 'web') {
      webContent.web = value;
    } else if (key === 'email') {
      emailContent.email = value;
    } else {
      uncategorizedContent[key] = value;
    }
  }

  // Write web.json
  const webPath = path.join(outputDir, 'web.json');
  fs.writeFileSync(webPath, JSON.stringify(webContent, null, 2) + '\n', 'utf-8');
  const webKeyCount = countKeys(webContent);
  console.log(`  ✓ web.json               (${webKeyCount} keys)`);

  // Write email.json
  const emailPath = path.join(outputDir, 'email.json');
  fs.writeFileSync(emailPath, JSON.stringify(emailContent, null, 2) + '\n', 'utf-8');
  const emailKeyCount = countKeys(emailContent);
  console.log(`  ✓ email.json             (${emailKeyCount} keys)`);

  // Write uncategorized.json
  const uncategorizedPath = path.join(outputDir, 'uncategorized.json');
  fs.writeFileSync(
    uncategorizedPath,
    JSON.stringify(uncategorizedContent, null, 2) + '\n',
    'utf-8'
  );
  const uncategorizedKeyCount = countKeys(uncategorizedContent);
  console.log(`  ✓ uncategorized.json     (${uncategorizedKeyCount} keys)`);

  console.log(`\n✅ Successfully split ${inputFilePath} into ${outputDir}/`);
  console.log(`   Next step: Run split-locale-step2.ts on ${path.join(outputDir, 'web.json')}`);
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
  const combinedData: any = {};

  // Read the three split files and combine
  const webPath = path.join(splitDir, 'web.json');
  const emailPath = path.join(splitDir, 'email.json');
  const uncategorizedPath = path.join(splitDir, 'uncategorized.json');

  if (fs.existsSync(webPath)) {
    const webData = JSON.parse(fs.readFileSync(webPath, 'utf-8'));
    Object.assign(combinedData, webData);
  }

  if (fs.existsSync(emailPath)) {
    const emailData = JSON.parse(fs.readFileSync(emailPath, 'utf-8'));
    Object.assign(combinedData, emailData);
  }

  if (fs.existsSync(uncategorizedPath)) {
    const uncategorizedData = JSON.parse(fs.readFileSync(uncategorizedPath, 'utf-8'));
    Object.assign(combinedData, uncategorizedData);
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
      path.join(debugDir, 'step1-original-sorted.json'),
      JSON.stringify(sortObjectKeys(originalData), null, 2) + '\n'
    );
    fs.writeFileSync(
      path.join(debugDir, 'step1-combined-sorted.json'),
      JSON.stringify(sortObjectKeys(combinedData), null, 2) + '\n'
    );
    console.error(`Debug files written to ${debugDir}/`);
    console.error(
      `Compare with: diff -u ${debugDir}/step1-original-sorted.json ${debugDir}/step1-combined-sorted.json`
    );

    return false;
  }
}

// Main execution
function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error(`Usage: ts-node split-locale-step1.ts <locale-file> [<locale-file2> ...]`);
    console.error(`Example: ts-node split-locale-step1.ts src/locales/en.json`);
    process.exit(1);
  }

  console.log('🌍 Locale Pre-processor Script (Step 1)');
  console.log('━'.repeat(60));

  for (const filePath of args) {
    try {
      splitByTopLevelStructure(filePath);

      // Verify
      const inputDir = path.dirname(filePath);
      const inputBasename = path.basename(filePath, path.extname(filePath));
      const outputDir = path.join(inputDir, inputBasename);

      verifyReversibility(filePath, outputDir);
    } catch (error) {
      console.error(`❌ Error processing ${filePath}:`, error);
    }
  }

  console.log('━'.repeat(60));
  console.log('✅ Step 1 complete!');
  console.log('📌 Next: Run split-locale-step2.ts on the generated web.json files');
}

main();
