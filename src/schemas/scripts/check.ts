#!/usr/bin/env tsx
// src/schemas/scripts/check.ts

/**
 * Validate a JSON document (e.g. an API response copied from the browser)
 * against a named Zod schema.
 *
 * Usage:
 *   pnpm -s exec tsx --tsconfig tsconfig.json src/schemas/scripts/check.ts --list
 *   pbpaste | pnpm -s exec tsx --tsconfig tsconfig.json src/schemas/scripts/check.ts v3.secret
 *   pnpm -s exec tsx --tsconfig tsconfig.json src/schemas/scripts/check.ts v2.receipt response.json
 *
 * Schema names are `<registry>.<key>` for the API response registries
 * (v1, v2, v3, incoming, internal) and the JSON Schema registry keys
 * (e.g. `shapes/secret`, `api/v3/secret-response`).
 *
 * Options:
 *   --show-values  Print the input value at each failing path. Off by default.
 *
 * Exit status: 0 valid, 1 invalid, 2 usage or input error.
 *
 * Privacy: responses can carry secret content, so by default failing values
 * are described by type and size (`string(24)`, `array(3)`), not content.
 * Key names and schema-provided messages are printed; custom messages must
 * not embed input values. The contents of `z.record` maps are not walked.
 *
 * Plain `z.object` strips unknown keys, so a payload can parse cleanly while
 * carrying fields the schema does not declare. Those are listed as
 * "undeclared", on success and on failure.
 */

import { readFileSync } from 'fs';

import { allSchemas, checkPayload, closest, counted, type Group } from '../check';
import { withoutSchemaDiagnostics } from '../validationContext';

function usage(message?: string): never {
  if (message) console.error(message);
  console.error('Usage: check.ts --list | check.ts [--show-values] <schema> [file]');
  console.error('Reads JSON from stdin when no file is given.');
  process.exit(2);
}

function printGroups(groups: Map<string, Group>): void {
  for (const [path, group] of groups) {
    console.log(path);
    if (group.missing.size) console.log(`  missing:    ${counted(group.missing).join(', ')}`);
    if (group.undeclared.size) console.log(`  undeclared: ${[...group.undeclared].join(', ')}`);
    for (const line of counted(group.problems)) console.log(`  ${line}`);
    console.log();
  }
}

// =============================================================================
// Main
// =============================================================================

const args = process.argv.slice(2);
const showValues = args.includes('--show-values');
const positional = args.filter((arg) => !arg.startsWith('--'));
const schemas = allSchemas();

if (args.includes('--list')) {
  console.log([...schemas.keys()].sort().join('\n'));
  process.exit(0);
}

const [name, file] = positional;
if (!name) usage();

const schema = schemas.get(name);
if (!schema) usage(`Unknown schema: ${name} (try --list)`);

if (!file && process.stdin.isTTY) usage('No input: pass a file or pipe JSON on stdin');

let input: unknown;
try {
  input = JSON.parse(readFileSync(file ?? 0, 'utf8'));
} catch (error) {
  // JSON.parse messages quote the input, so report only the error class.
  usage(`Could not read JSON (${(error as Error).name})`);
}

const result = withoutSchemaDiagnostics(() => checkPayload(schema, input, showValues));

if (result.success) {
  console.log(`OK: valid against ${name}`);
  if (result.undeclared.length > 0) {
    console.log(`\nUndeclared keys, stripped by the schema (${result.undeclared.length}):`);
    for (const key of result.undeclared) console.log(`  ${key}`);
  }
  process.exit(0);
}

const hidden = showValues ? '' : ' Values hidden; --show-values prints them at failing paths.';
console.log(`INVALID against ${name}: ${result.issueCount} issues.${hidden}\n`);
printGroups(result.groups);

console.log('Closest schemas (by fields recognised):');
for (const c of withoutSchemaDiagnostics(() => closest(input, schemas))) {
  const status = c.issues === 0 ? 'valid' : `${c.issues} issues`;
  console.log(
    `  ${c.name.padEnd(36)} ${String(c.matched).padStart(4)} matched  ${status}, ${c.undeclared} undeclared`
  );
}
process.exit(1);
