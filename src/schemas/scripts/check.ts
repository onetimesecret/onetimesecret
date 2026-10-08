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
 * Privacy: responses can carry secret content, so by default the output never
 * contains an input value. Failing values are described by type and size
 * (`string(24)`, `array(3)`), which keeps the report safe to paste into an
 * issue. Key names are printed; the contents of `z.record` maps are not walked.
 *
 * Plain `z.object` strips unknown keys, so a payload can parse cleanly while
 * carrying fields the schema does not declare. Those are listed as
 * "undeclared", on success and on failure.
 */

import { readFileSync } from 'fs';
import { z } from 'zod';

import { responseSchemas as incoming } from '../api/incoming/responses/registry';
import { responseSchemas as internal } from '../api/internal/responses/registry';
import { responseSchemas as v1 } from '../api/v1/responses/registry';
import { responseSchemas as v2 } from '../api/v2/responses/registry';
import { responseSchemas as v3 } from '../api/v3/responses/registry';
import { schemaRegistry } from '../registry';

type Path = readonly PropertyKey[];

const registries: Record<string, Record<string, z.ZodType>> = { v1, v2, v3, incoming, internal };

function allSchemas(): Map<string, z.ZodType> {
  const map = new Map<string, z.ZodType>();
  for (const [prefix, registry] of Object.entries(registries)) {
    for (const [key, schema] of Object.entries(registry)) map.set(`${prefix}.${key}`, schema);
  }
  for (const [key, schema] of Object.entries(schemaRegistry)) map.set(key, schema as z.ZodType);
  return map;
}

function usage(message?: string): never {
  if (message) console.error(message);
  console.error('Usage: check.ts --list | check.ts [--show-values] <schema> [file]');
  console.error('Reads JSON from stdin when no file is given.');
  process.exit(2);
}

// =============================================================================
// Paths and values
// =============================================================================

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' && value !== null && Object.getPrototypeOf(value) === Object.prototype
  );
}

/** Exact path, used to match issues to input positions. */
function pathKey(path: Path): string {
  return JSON.stringify(path.map(String));
}

/** Display path. Array indices collapse to [*] so list items group together. */
function formatPath(path: Path): string {
  let out = '';
  for (const seg of path) {
    if (typeof seg === 'number') out += '[*]';
    else out += out ? `.${String(seg)}` : String(seg);
  }
  return out || '(root)';
}

function valueAt(input: unknown, path: Path): unknown {
  let current = input;
  for (const seg of path) {
    if (current === null || typeof current !== 'object') return undefined;
    current = (current as Record<PropertyKey, unknown>)[seg];
  }
  return current;
}

/** Type and size of a value, never its content. */
function describe(value: unknown): string {
  if (value === undefined) return 'missing';
  if (value === null) return 'null';
  if (typeof value === 'string') return `string(${value.length})`;
  if (Array.isArray(value)) return `array(${value.length})`;
  if (typeof value === 'object') return `object(${Object.keys(value).length} keys)`;
  return typeof value;
}

function reveal(value: unknown): string {
  const json = JSON.stringify(value) ?? String(value);
  return json.length > 80 ? `${json.slice(0, 77)}...` : json;
}

// =============================================================================
// Schema introspection
// =============================================================================

interface Def {
  type: string;
  innerType?: z.core.$ZodType;
  in?: z.core.$ZodType;
  out?: z.core.$ZodType;
  getter?: () => z.core.$ZodType;
  shape?: Record<string, z.core.$ZodType>;
  element?: z.core.$ZodType;
}

function defOf(schema: z.core.$ZodType): Def {
  return schema._zod.def as unknown as Def;
}

/**
 * Strip wrappers (optional, nullable, default, lazy, transform pipes) down to
 * the schema that checks the input. `z.preprocess` is a pipe whose input side
 * is a transform, so its output side is the one that describes the shape.
 */
function unwrap(schema: z.core.$ZodType): z.core.$ZodType {
  let current = schema;
  for (let depth = 0; depth < 32; depth++) {
    const def = defOf(current);
    let next: z.core.$ZodType | undefined;
    if (def.innerType) next = def.innerType;
    else if (def.type === 'lazy') next = def.getter?.();
    else if (def.type === 'pipe' && def.in) {
      next = defOf(unwrap(def.in)).type === 'transform' ? def.out : def.in;
    }
    if (!next) return current;
    current = next;
  }
  return current;
}

interface Coverage {
  /** Leaf positions in the input that the schema declares and accepted. */
  matched: number;
  /** Input keys the schema does not declare, by display path. */
  undeclared: Map<string, Path>;
}

function coverage(schema: z.ZodType, input: unknown, issuePaths: Set<string>): Coverage {
  const result: Coverage = { matched: 0, undeclared: new Map() };
  const visit = (node: z.core.$ZodType, value: unknown, path: Path): void => {
    const def = defOf(unwrap(node));
    if (def.type === 'object' && def.shape && isPlainObject(value)) {
      for (const [key, child] of Object.entries(value)) {
        const childPath = [...path, key];
        if (key in def.shape) visit(def.shape[key], child, childPath);
        else result.undeclared.set(formatPath(childPath), childPath);
      }
    } else if (def.type === 'array' && def.element && Array.isArray(value)) {
      value.forEach((item, i) => visit(def.element!, item, [...path, i]));
    } else if (!issuePaths.has(pathKey(path))) {
      result.matched++;
    }
  };
  visit(schema, input, []);
  return result;
}

// =============================================================================
// Reporting
// =============================================================================

interface Group {
  missing: Map<string, number>;
  problems: Map<string, number>;
  undeclared: Set<string>;
}

function counted(map: Map<string, number>): string[] {
  return [...map].map(([text, n]) => (n > 1 ? `${text} (x${n})` : text));
}

function explain(issue: z.core.$ZodIssue, value: unknown, showValues: boolean): string {
  const got = showValues ? `${describe(value)} ${reveal(value)}` : describe(value);
  switch (issue.code) {
    case 'invalid_type':
      return `expected ${issue.expected}, got ${got}`;
    case 'invalid_value':
      return `expected ${issue.values.map((v) => reveal(v)).join(' | ')}, got ${got}`;
    default:
      return `${issue.message} (input: ${got})`;
  }
}

interface Failure {
  schema: z.ZodType;
  input: unknown;
  issues: z.core.$ZodIssue[];
}

/** Issues and undeclared keys, grouped by the object that holds them. */
function groupFailure({ schema, input, issues }: Failure, showValues: boolean): Map<string, Group> {
  const groups = new Map<string, Group>();
  const groupFor = (path: Path): Group => {
    const key = formatPath(path);
    let group = groups.get(key);
    if (!group) {
      group = { missing: new Map(), problems: new Map(), undeclared: new Set() };
      groups.set(key, group);
    }
    return group;
  };
  const bump = (map: Map<string, number>, text: string) => map.set(text, (map.get(text) ?? 0) + 1);

  for (const issue of issues) {
    const leaf = issue.path.length > 0 ? formatPath(issue.path.slice(-1)) : '(root)';
    const value = valueAt(input, issue.path);
    const group = groupFor(issue.path.slice(0, -1));
    if (value === undefined && issue.path.length > 0) bump(group.missing, leaf);
    else bump(group.problems, `${leaf}: ${explain(issue, value, showValues)}`);
  }

  const issuePaths = new Set(issues.map((issue) => pathKey(issue.path)));
  for (const path of coverage(schema, input, issuePaths).undeclared.values()) {
    groupFor(path.slice(0, -1)).undeclared.add(formatPath(path.slice(-1)));
  }
  return groups;
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

interface Candidate {
  name: string;
  issues: number;
  matched: number;
  undeclared: number;
}

/** Rank API schemas by how much of the input they recognise. */
function closest(input: unknown, schemas: Map<string, z.ZodType>, limit = 3): Candidate[] {
  const candidates: Candidate[] = [];
  const seen = new Set<z.ZodType>();
  for (const [name, schema] of schemas) {
    // Registry aliases (api/v3/secret-response is v3.secret) would rank twice.
    if (name.startsWith('config/') || seen.has(schema)) continue;
    seen.add(schema);
    let issues: z.core.$ZodIssue[];
    try {
      const result = schema.safeParse(input);
      issues = result.success ? [] : result.error.issues;
    } catch {
      continue; // async refinements or a transform that throws
    }
    const cov = coverage(schema, input, new Set(issues.map((issue) => pathKey(issue.path))));
    candidates.push({
      name,
      issues: issues.length,
      matched: cov.matched,
      undeclared: cov.undeclared.size,
    });
  }
  return candidates
    .sort((a, b) => b.matched - a.matched || a.issues - b.issues || a.undeclared - b.undeclared)
    .slice(0, limit);
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

const result = schema.safeParse(input);

if (result.success) {
  console.log(`OK: valid against ${name}`);
  const undeclared = [...coverage(schema, input, new Set()).undeclared.keys()];
  if (undeclared.length > 0) {
    console.log(`\nUndeclared keys, stripped by the schema (${undeclared.length}):`);
    for (const key of undeclared) console.log(`  ${key}`);
  }
  process.exit(0);
}

const hidden = showValues ? '' : ' Values hidden; --show-values prints them at failing paths.';
console.log(`INVALID against ${name}: ${result.error.issues.length} issues.${hidden}\n`);
printGroups(groupFailure({ schema, input, issues: result.error.issues }, showValues));

console.log('Closest schemas (by fields recognised):');
for (const c of closest(input, schemas)) {
  const status = c.issues === 0 ? 'valid' : `${c.issues} issues`;
  console.log(
    `  ${c.name.padEnd(36)} ${String(c.matched).padStart(4)} matched  ${status}, ${c.undeclared} undeclared`
  );
}
process.exit(1);
