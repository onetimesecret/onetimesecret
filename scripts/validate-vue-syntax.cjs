#!/usr/bin/env node

const fs = require('fs');
const { execSync } = require('child_process');

// Find all .vue files
const vueFiles = execSync('find src -name "*.vue" -type f', { encoding: 'utf8' })
  .trim()
  .split('\n')
  .filter(Boolean);

const corrupted = [];

for (const file of vueFiles) {
  try {
    const content = fs.readFileSync(file, 'utf8');
    const scriptMatch = content.match(/<script[^>]*>([\s\S]*?)<\/script>/);

    if (!scriptMatch) continue;

    const scriptContent = scriptMatch[1];
    const issues = [];

    // Check for actual corruption patterns
    const lines = scriptContent.split('\n');

    lines.forEach((line, idx) => {
      // Pattern 1: import statement incomplete (ends abruptly)
      if (/^import\s+$/.test(line.trim())) {
        issues.push(`Line ${idx + 1}: Incomplete import`);
      }

      // Pattern 2: Code merged after useI18n() on same line
      if (/const\s+\{\s*t\s*\}\s*=\s*useI18n\(\);[a-zA-Z{]/.test(line)) {
        issues.push(`Line ${idx + 1}: Code merged after useI18n()`);
      }

      // Pattern 3: Broken import from statement
      if (/^import.*from\s+['"][^'"]*$/.test(line.trim()) && !line.includes(';')) {
        const nextLine = lines[idx + 1]?.trim() || '';
        if (!nextLine.startsWith('\'') && !nextLine.startsWith('"')) {
          issues.push(`Line ${idx + 1}: Incomplete from clause`);
        }
      }

      // Pattern 4: Import with unclosed braces
      if (/^import\s+\{[^}]*$/.test(line.trim()) && !line.includes('from')) {
        const nextLine = lines[idx + 1]?.trim() || '';
        if (!nextLine.includes('}') && !nextLine.includes('from')) {
          issues.push(`Line ${idx + 1}: Unclosed import braces`);
        }
      }
    });

    if (issues.length > 0) {
      corrupted.push({ file, issues });
    }

  } catch (error) {
    console.error(`Error reading ${file}:`, error.message);
  }
}

if (corrupted.length === 0) {
  console.log('✅ No corruption detected in Vue files!');
  process.exit(0);
} else {
  console.log(`❌ Found ${corrupted.length} corrupted Vue file(s):\n`);

  for (const { file, issues } of corrupted) {
    console.log(`${file}:`);
    issues.forEach(issue => console.log(`  - ${issue}`));
    console.log('');
  }

  process.exit(1);
}
