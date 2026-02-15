#!/usr/bin/env node

/**
 * Renames all "web.private.*" keys to "web.receipt.*" in every
 * locales/content/<locale>/secret-manage.json file.
 *
 * Usage: node locales/scripts/rename-private-to-receipt.mjs [--dry-run]
 */

import { readFileSync, writeFileSync, readdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const contentDir = join(__dirname, '..', 'content');
const dryRun = process.argv.includes('--dry-run');

const locales = readdirSync(contentDir, { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => d.name);

let totalRenamed = 0;
let filesModified = 0;

for (const locale of locales) {
  const filePath = join(contentDir, locale, 'secret-manage.json');
  let raw;
  try {
    raw = readFileSync(filePath, 'utf-8');
  } catch {
    console.log(`  SKIP ${locale}/secret-manage.json (not found)`);
    continue;
  }

  const data = JSON.parse(raw);
  const newData = {};
  let renamedInFile = 0;

  for (const [key, value] of Object.entries(data)) {
    if (key.startsWith('web.private.')) {
      const newKey = key.replace('web.private.', 'web.receipt.');
      newData[newKey] = value;
      renamedInFile++;
    } else {
      newData[key] = value;
    }
  }

  if (renamedInFile > 0) {
    if (!dryRun) {
      writeFileSync(filePath, JSON.stringify(newData, null, 2) + '\n', 'utf-8');
    }
    console.log(`  ${dryRun ? '[DRY RUN] ' : ''}${locale}: renamed ${renamedInFile} keys`);
    totalRenamed += renamedInFile;
    filesModified++;
  }
}

console.log(
  `\n${dryRun ? '[DRY RUN] ' : ''}Done: ${totalRenamed} keys renamed across ${filesModified} files.`
);
