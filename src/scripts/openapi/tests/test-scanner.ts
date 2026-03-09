// src/scripts/openapi/tests/test-scanner.ts

/**
 * Test Schema Scanner
 *
 * Validates the scanner discovers SCHEMA constants in Ruby source files,
 * resolves them against the responseSchemas registry, and produces
 * meaningful coverage gap reports when combined with route data.
 */

import { scanSchemas, buildHandlerSchemaMap } from '../schema-scanner';
import { responseSchemas } from '@/schemas/api/v3/responses';

console.log('Testing Schema Scanner...\n');

let passed = 0;
let failed = 0;

function pass(msg: string): void {
  passed++;
  console.log(`  PASS: ${msg}`);
}

function fail(msg: string): void {
  failed++;
  console.log(`  FAIL: ${msg}`);
}

// Scan once (async) and run all tests against the result
const result = await scanSchemas();

// ---------------------------------------------------------------------------
// Test 1: Scanner discovers SCHEMA entries
// ---------------------------------------------------------------------------
console.log('Test 1: Scanner discovers SCHEMA entries');
try {
  const count = result.entries.length;

  if (count >= 55) {
    pass(`Found ${count} SCHEMA entries (expected >= 55)`);
  } else {
    fail(`Found only ${count} SCHEMA entries (expected >= 55)`);
  }

  // Verify some known entries exist
  const classNames = new Set(result.entries.map(e => e.className));
  const expected = [
    'V3::Logic::Secrets::ConcealSecret',
    'V3::Logic::Secrets::RevealSecret',
    'V3::Logic::Secrets::BurnSecret',
    'AccountAPI::Logic::Account::GetAccount',
    'ColonelAPI::Logic::Colonel::GetColonelInfo',
    'DomainsAPI::Logic::Domains::AddDomain',
    'OrganizationAPI::Logic::Organizations::CreateOrganization',
    'Onetime::Secret',
    'Onetime::Customer',
  ];

  let missingCount = 0;
  for (const name of expected) {
    if (!classNames.has(name)) {
      fail(`Missing expected class: ${name}`);
      missingCount++;
    }
  }
  if (missingCount === 0) {
    pass(`All ${expected.length} expected classes found`);
  }
  console.log('');
} catch (error) {
  fail(`Scanner threw: ${error}`);
  console.log('');
}

// ---------------------------------------------------------------------------
// Test 2: SCHEMA values resolve to responseSchemas keys
// ---------------------------------------------------------------------------
console.log('Test 2: Response keys resolve to responseSchemas registry');
try {
  const registryKeys = new Set(Object.keys(responseSchemas));

  // Check covered entries have valid response keys
  for (const entry of result.covered) {
    const key = entry.schema.response;
    if (key && !registryKeys.has(key)) {
      fail(`Covered entry ${entry.className} has key "${key}" not in responseSchemas`);
    }
  }

  if (result.covered.length > 0) {
    pass(`${result.covered.length} covered entries all resolve to valid responseSchemas keys`);
  } else {
    fail('No covered entries found');
  }

  // Broken entries should have keys NOT in the registry
  for (const entry of result.broken) {
    const key = entry.schema.response;
    if (key && registryKeys.has(key)) {
      fail(`Broken entry ${entry.className} has key "${key}" that IS in responseSchemas`);
    }
  }
  if (result.broken.length > 0) {
    pass(`${result.broken.length} broken entries correctly flagged (keys not in registry)`);
  }
  console.log('');
} catch (error) {
  fail(`Resolution check threw: ${error}`);
  console.log('');
}

// ---------------------------------------------------------------------------
// Test 3: Handler map lookup works (FQCN and leaf name)
// ---------------------------------------------------------------------------
console.log('Test 3: Handler map lookup (FQCN and leaf name)');
try {
  const handlerMap = buildHandlerSchemaMap(result.entries);

  // FQCN lookup
  const fqcnEntry = handlerMap.get('V3::Logic::Secrets::ConcealSecret');
  if (fqcnEntry) {
    pass('FQCN lookup works: V3::Logic::Secrets::ConcealSecret');
  } else {
    fail('FQCN lookup failed for V3::Logic::Secrets::ConcealSecret');
  }

  // Leaf name lookup
  const leafEntry = handlerMap.get('GetColonelInfo');
  if (leafEntry) {
    pass(`Leaf lookup works: GetColonelInfo -> ${leafEntry.className}`);
  } else {
    fail('Leaf lookup failed for GetColonelInfo');
  }

  // Map size should be > entries count (due to leaf aliases)
  if (handlerMap.size > result.entries.length) {
    pass(`Handler map has ${handlerMap.size} entries (${result.entries.length} SCHEMA + leaf aliases)`);
  } else {
    fail(`Handler map size ${handlerMap.size} should exceed entry count ${result.entries.length}`);
  }
  console.log('');
} catch (error) {
  fail(`Handler map test threw: ${error}`);
  console.log('');
}

// ---------------------------------------------------------------------------
// Test 4: Coverage stats from scanner + routes join
// ---------------------------------------------------------------------------
console.log('Test 4: Scanner + routes coverage stats');
try {
  const totalWithSchema = result.entries.length;
  const totalHandlers = result.uncoveredHandlers.length + totalWithSchema;
  const coveragePercent = totalHandlers > 0
    ? Math.round((totalWithSchema / totalHandlers) * 100)
    : 0;

  pass(`Handler coverage: ${totalWithSchema}/${totalHandlers} (${coveragePercent}%)`);

  const modelEntries = result.entries.filter(e => e.filePath.startsWith('lib/onetime/models/'));
  const totalModels = modelEntries.length + result.uncoveredModels.length;
  const modelCoverage = totalModels > 0
    ? Math.round((modelEntries.length / totalModels) * 100)
    : 0;

  pass(`Model coverage: ${modelEntries.length}/${totalModels} (${modelCoverage}%)`);

  if (coveragePercent > 40) {
    pass(`Coverage is above minimum threshold (${coveragePercent}% > 40%)`);
  } else {
    fail(`Coverage below threshold: ${coveragePercent}% (expected > 40%)`);
  }
  console.log('');
} catch (error) {
  fail(`Coverage stats threw: ${error}`);
  console.log('');
}

// ---------------------------------------------------------------------------
// Test 5: Gap report identifies known uncovered handlers
// ---------------------------------------------------------------------------
console.log('Test 5: Gap report identifies known uncovered handlers');
try {
  // These handlers were intentionally skipped (no schema defined)
  const knownGaps = [
    'DestroyAccount',
    'UpdatePassword',
    'UpdateLocale',
  ];

  let foundGaps = 0;
  for (const gap of knownGaps) {
    const found = result.uncoveredHandlers.some(h => h.includes(gap));
    if (found) {
      foundGaps++;
    } else {
      fail(`Expected uncovered handler containing "${gap}" not found in gap report`);
    }
  }

  if (foundGaps === knownGaps.length) {
    pass(`All ${knownGaps.length} known gap handlers correctly identified as uncovered`);
  }

  // Known uncovered models (CustomDomain & Organization now have SCHEMA constants)
  const knownUncoveredModels = ['Onetime::Features', 'Onetime::OrganizationMembership'];
  let foundModels = 0;
  for (const model of knownUncoveredModels) {
    if (result.uncoveredModels.includes(model)) {
      foundModels++;
    } else {
      fail(`Expected uncovered model "${model}" not found in gap report`);
    }
  }

  if (foundModels === knownUncoveredModels.length) {
    pass(`All ${knownUncoveredModels.length} known uncovered models correctly identified`);
  }
  console.log('');
} catch (error) {
  fail(`Gap report test threw: ${error}`);
  console.log('');
}

// ---------------------------------------------------------------------------
// Test 6: V2 and V3 classes share same response schemas
// ---------------------------------------------------------------------------
console.log('Test 6: V2/V3 schema parity');
try {
  // Build maps by leaf class name for V2 and V3
  const v2Entries = new Map<string, string>();
  const v3Entries = new Map<string, string>();

  for (const entry of result.entries) {
    const leaf = entry.className.split('::').pop() ?? '';
    const responseKey = entry.schema.response ?? '';

    if (entry.className.startsWith('V2::')) {
      v2Entries.set(leaf, responseKey);
    } else if (entry.className.startsWith('V3::')) {
      v3Entries.set(leaf, responseKey);
    }
  }

  // Find shared class names and verify same response key
  let matched = 0;
  let mismatched = 0;
  for (const [leaf, v2Key] of v2Entries) {
    const v3Key = v3Entries.get(leaf);
    if (v3Key !== undefined) {
      if (v2Key === v3Key) {
        matched++;
      } else {
        fail(`V2/V3 mismatch for ${leaf}: V2="${v2Key}" vs V3="${v3Key}"`);
        mismatched++;
      }
    }
  }

  if (matched > 0 && mismatched === 0) {
    pass(`${matched} V2/V3 class pairs have matching response schemas`);
  }
  console.log('');
} catch (error) {
  fail(`V2/V3 parity test threw: ${error}`);
  console.log('');
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
console.log('─────────────────────────────────────────');
console.log(`Results: ${passed} passed, ${failed} failed`);
console.log('');

if (failed > 0) {
  console.log('Some scanner tests failed.');
  process.exit(1);
} else {
  console.log('All scanner tests passed.');
  console.log('Scanner is ready for OpenAPI generation integration.');
}
