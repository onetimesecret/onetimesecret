#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const LOCALES_DIR = './src/locales';
const EN_DIR = path.join(LOCALES_DIR, 'en');

// Get all locale directories except 'en' and non-directories
const locales = fs.readdirSync(LOCALES_DIR)
  .filter(item => {
    const fullPath = path.join(LOCALES_DIR, item);
    return fs.statSync(fullPath).isDirectory() && item !== 'en';
  });

// Get all JSON files from English locale
const jsonFiles = fs.readdirSync(EN_DIR)
  .filter(file => file.endsWith('.json'));

console.log('='.repeat(80));
console.log('MISSING TRANSLATIONS AUDIT REPORT');
console.log('='.repeat(80));
console.log(`Checking ${locales.length} locales against ${jsonFiles.length} JSON files\n`);

const results = {};

// Function to deeply traverse an object and find all key paths
function getAllKeyPaths(obj, currentPath = '', paths = []) {
  for (const [key, value] of Object.entries(obj)) {
    const fullPath = currentPath ? `${currentPath}.${key}` : key;

    if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
      getAllKeyPaths(value, fullPath, paths);
    } else {
      paths.push({ path: fullPath, value });
    }
  }
  return paths;
}

// Function to check if a value is likely English text
function isLikelyEnglish(value, enValue) {
  if (typeof value !== 'string') return false;
  if (value === '') return false; // Empty strings are not considered English

  // If it matches the English value exactly, it's English
  if (value === enValue) return true;

  // Check for common English words (basic heuristic)
  const commonEnglishWords = [
    'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'can', 'had',
    'her', 'was', 'one', 'our', 'out', 'day', 'get', 'has', 'him', 'his',
    'how', 'man', 'new', 'now', 'old', 'see', 'time', 'two', 'way', 'who',
    'account', 'password', 'email', 'settings', 'create', 'delete', 'update',
    'secret', 'link', 'share', 'burn', 'view', 'expires', 'expired'
  ];

  const lowerValue = value.toLowerCase();
  const words = lowerValue.split(/\s+/);

  // If it contains multiple common English words, it's likely English
  const englishWordCount = words.filter(word =>
    commonEnglishWords.includes(word.replace(/[^a-z]/g, ''))
  ).length;

  return englishWordCount >= 2 || (words.length <= 3 && englishWordCount >= 1);
}

// Check each locale
for (const locale of locales) {
  results[locale] = {};
  let totalMissing = 0;

  for (const jsonFile of jsonFiles) {
    const enPath = path.join(EN_DIR, jsonFile);
    const localePath = path.join(LOCALES_DIR, locale, jsonFile);

    // Skip if locale file doesn't exist
    if (!fs.existsSync(localePath)) {
      continue;
    }

    try {
      const enData = JSON.parse(fs.readFileSync(enPath, 'utf8'));
      const localeData = JSON.parse(fs.readFileSync(localePath, 'utf8'));

      const enPaths = getAllKeyPaths(enData);
      const missing = [];

      for (const { path: keyPath, value: enValue } of enPaths) {
        // Skip keys that start with underscore (intentionally English)
        const keyParts = keyPath.split('.');
        const lastKey = keyParts[keyParts.length - 1];
        if (lastKey.startsWith('_')) {
          continue;
        }

        // Get the value from locale data
        let localeValue = localeData;
        let found = true;
        for (const part of keyParts) {
          if (localeValue && typeof localeValue === 'object' && part in localeValue) {
            localeValue = localeValue[part];
          } else {
            found = false;
            break;
          }
        }

        // Check if the key is missing or has English content
        if (!found || isLikelyEnglish(localeValue, enValue)) {
          missing.push({
            key: keyPath,
            enValue: enValue,
            localeValue: found ? localeValue : '[MISSING]'
          });
        }
      }

      if (missing.length > 0) {
        results[locale][jsonFile] = missing;
        totalMissing += missing.length;
      }

    } catch (error) {
      console.error(`Error processing ${locale}/${jsonFile}: ${error.message}`);
    }
  }

  // Print results for this locale
  if (totalMissing > 0) {
    console.log(`\n${'='.repeat(80)}`);
    console.log(`LOCALE: ${locale.toUpperCase()} - ${totalMissing} missing translations`);
    console.log('='.repeat(80));

    for (const [file, missing] of Object.entries(results[locale])) {
      console.log(`\n  ${file} (${missing.length} missing):`);
      console.log('  ' + '-'.repeat(76));

      for (const { key, enValue, localeValue } of missing) {
        console.log(`    • ${key}`);
        console.log(`      EN: "${enValue}"`);
        console.log(`      ${locale.toUpperCase()}: "${localeValue}"`);
      }
    }
  }
}

// Summary
console.log(`\n${'='.repeat(80)}`);
console.log('SUMMARY');
console.log('='.repeat(80));

let grandTotal = 0;
const summary = [];

for (const locale of locales) {
  const localeTotal = Object.values(results[locale])
    .reduce((sum, missing) => sum + missing.length, 0);

  if (localeTotal > 0) {
    summary.push({ locale, count: localeTotal });
    grandTotal += localeTotal;
  }
}

// Sort by count descending
summary.sort((a, b) => b.count - a.count);

for (const { locale, count } of summary) {
  console.log(`  ${locale.padEnd(10)} : ${count.toString().padStart(4)} missing translations`);
}

console.log('  ' + '-'.repeat(76));
console.log(`  ${'TOTAL'.padEnd(10)} : ${grandTotal.toString().padStart(4)} missing translations`);
console.log('='.repeat(80));
