// src/scripts/openapi/generate-all-specs.ts

/**
 * Generate All OpenAPI Specifications
 *
 * Master script that generates OpenAPI 3.0.3 specifications for all APIs:
 * - V3 API (public secrets)
 * - Account API (account management)
 * - V2 API (legacy)
 * - Domains API
 * - Organizations API
 * - Teams API
 */

import { execSync } from 'child_process';

console.log('🚀 Generating OpenAPI specifications for all APIs...\n');

const generators = [
  { name: 'V3 API', script: 'pnpm run openapi:generate:v3' },
  { name: 'Account API', script: 'pnpm run openapi:generate:account' },
];

let successCount = 0;
let failCount = 0;

for (const generator of generators) {
  try {
    console.log(`\n${'='.repeat(80)}`);
    console.log(`Running ${generator.name} generator...`);
    console.log(`${'='.repeat(80)}\n`);

    execSync(generator.script, { stdio: 'inherit' });
    successCount++;

    console.log(`\n✅ ${generator.name} spec generated successfully\n`);
  } catch (error) {
    console.error(`\n❌ ${generator.name} spec generation failed ${error}\n`);
    failCount++;
  }
}

console.log(`\n${'='.repeat(80)}`);
console.log('📊 Generation Summary');
console.log(`${'='.repeat(80)}\n`);
console.log(`✅ Successful: ${successCount}/${generators.length}`);
console.log(`❌ Failed: ${failCount}/${generators.length}`);

if (failCount === 0) {
  console.log(`\n🎉 All OpenAPI specifications generated successfully!\n`);
  process.exit(0);
} else {
  console.log(`\n⚠️  Some specifications failed to generate. See errors above.\n`);
  process.exit(1);
}
