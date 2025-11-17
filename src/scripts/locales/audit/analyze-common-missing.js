#!/usr/bin/env node

import fs from 'fs';

const reportPath = './translation-audit-report.txt';
const content = fs.readFileSync(reportPath, 'utf8');

// Track which keys are missing across multiple locales
const keyStats = {};

const localeBlocks = content.split(/^LOCALE: /m).slice(1);

for (const block of localeBlocks) {
  const lines = block.split('\n');
  const localeLine = lines[0];
  const locale = localeLine.split(' - ')[0].trim();

  // Find all missing keys
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const keyMatch = line.match(/^\s{4}• (.+)$/);

    if (keyMatch) {
      const key = keyMatch[1];
      const enLine = lines[i + 1];
      const localeLine = lines[i + 2];

      if (enLine && localeLine) {
        const enMatch = enLine.match(/EN: "(.+)"$/);
        const enValue = enMatch ? enMatch[1] : '[unknown]';

        if (!keyStats[key]) {
          keyStats[key] = {
            enValue,
            count: 0,
            locales: []
          };
        }

        keyStats[key].count++;
        keyStats[key].locales.push(locale);
      }
    }
  }
}

// Sort by count (most commonly missing)
const sortedKeys = Object.entries(keyStats)
  .sort((a, b) => b[1].count - a[1].count)
  .slice(0, 50); // Top 50

console.log('='.repeat(80));
console.log('TOP 50 MOST COMMONLY MISSING KEYS ACROSS ALL LOCALES');
console.log('='.repeat(80));
console.log('These keys are missing in multiple locales and are good candidates for');
console.log('batch translation efforts.\n');

for (const [key, stats] of sortedKeys) {
  console.log(`Missing in ${stats.count}/27 locales: ${key}`);
  console.log(`  English: "${stats.enValue.substring(0, 80)}${stats.enValue.length > 80 ? '...' : ''}"`);
  console.log(`  Locales: ${stats.locales.join(', ')}`);
  console.log('');
}

console.log('='.repeat(80));
