#!/usr/bin/env node

import fs from 'fs';
import path from 'path';

const reportPath = './translation-audit-report.txt';
const content = fs.readFileSync(reportPath, 'utf8');

// Parse the report to count issues by file across all locales
const fileStats = {};

const localeBlocks = content.split(/^LOCALE: /m).slice(1);

for (const block of localeBlocks) {
  const lines = block.split('\n');
  const localeLine = lines[0];
  const locale = localeLine.split(' - ')[0].trim();

  // Find all file sections
  const fileRegex = /^\s\s(\S+\.json)\s+\((\d+)\s+missing\):/gm;
  let match;

  while ((match = fileRegex.exec(block)) !== null) {
    const fileName = match[1];
    const count = parseInt(match[2]);

    if (!fileStats[fileName]) {
      fileStats[fileName] = {
        totalMissing: 0,
        affectedLocales: 0,
        locales: []
      };
    }

    fileStats[fileName].totalMissing += count;
    fileStats[fileName].affectedLocales++;
    fileStats[fileName].locales.push({ locale, count });
  }
}

// Sort by total missing
const sortedFiles = Object.entries(fileStats)
  .sort((a, b) => b[1].totalMissing - a[1].totalMissing);

console.log('='.repeat(80));
console.log('MISSING TRANSLATIONS BY FILE');
console.log('='.repeat(80));
console.log('');

for (const [fileName, stats] of sortedFiles) {
  console.log(`${fileName}`);
  console.log(`  Total missing: ${stats.totalMissing}`);
  console.log(`  Affected locales: ${stats.affectedLocales}/27`);
  console.log(`  Average per locale: ${Math.round(stats.totalMissing / stats.affectedLocales)}`);

  // Show top 5 locales for this file
  const topLocales = stats.locales
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);

  console.log(`  Top affected: ${topLocales.map(l => `${l.locale}(${l.count})`).join(', ')}`);
  console.log('');
}

console.log('='.repeat(80));
