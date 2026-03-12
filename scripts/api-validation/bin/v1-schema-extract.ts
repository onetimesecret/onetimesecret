#!/usr/bin/env -S npx tsx
/**
 * v1-schema-extract.ts
 *
 * Extracts V1 API response schemas from actual captured responses (v0.23.6)
 * and compares them against the Zod schemas defined in main branch.
 *
 * This script does two things:
 *   1. Infers JSON Schema from captured response bodies (structural inference)
 *   2. Generates a comparison report: inferred vs declared schemas
 *
 * Usage:
 *   npx tsx v1-schema-extract.ts <captures_dir> [output_file]
 *
 * Example:
 *   npx tsx v1-schema-extract.ts ./captures/v0.23.6/20260217-120000 ./diffs/schema-inference.json
 */

import { readFileSync, readdirSync, writeFileSync, existsSync } from 'fs';
import { join, basename } from 'path';

// ─── Types ────────────────────────────────────────────────────────────

interface InferredField {
  type: string;
  nullable: boolean;
  optional: boolean;  // absent in some responses for same endpoint
  example: unknown;
  variants?: string[];  // for string enums (state fields, etc.)
}

interface InferredSchema {
  endpoint: string;
  method: string;
  status: number;
  fields: Record<string, InferredField>;
  sample_count: number;
}

interface CaptureFile {
  test_name: string;
  request: {
    method: string;
    path: string;
  };
  response: {
    status: number;
    body: unknown;
  };
}

// ─── Schema Inference ─────────────────────────────────────────────────

function inferType(value: unknown): string {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  return typeof value;
}

function mergeFieldInfo(
  existing: InferredField | undefined,
  value: unknown,
  fieldName: string
): InferredField {
  const type = inferType(value);

  if (!existing) {
    const field: InferredField = {
      type: type === 'null' ? 'unknown' : type,
      nullable: value === null,
      optional: false,
      example: value,
    };
    // Track string values that look like enums (state, role, etc.)
    if (type === 'string' && typeof value === 'string') {
      const enumLike = ['state', 'role', 'kind', 'status', 'type', 'plan'];
      if (enumLike.some(e => fieldName.toLowerCase().includes(e))) {
        field.variants = [value];
      }
    }
    return field;
  }

  // Merge types
  if (type === 'null') {
    existing.nullable = true;
  } else if (existing.type === 'unknown') {
    existing.type = type;
  } else if (existing.type !== type) {
    existing.type = `${existing.type} | ${type}`;
  }

  // Track enum variants
  if (type === 'string' && existing.variants && typeof value === 'string') {
    if (!existing.variants.includes(value)) {
      existing.variants.push(value);
    }
  }

  return existing;
}

function inferSchemaFromBody(body: unknown): Record<string, InferredField> {
  const fields: Record<string, InferredField> = {};

  if (body && typeof body === 'object' && !Array.isArray(body)) {
    for (const [key, value] of Object.entries(body as Record<string, unknown>)) {
      fields[key] = mergeFieldInfo(undefined, value, key);

      // One level of nesting for objects
      if (value && typeof value === 'object' && !Array.isArray(value)) {
        for (const [subKey, subValue] of Object.entries(value as Record<string, unknown>)) {
          fields[`${key}.${subKey}`] = mergeFieldInfo(undefined, subValue, subKey);
        }
      }
    }
  }

  return fields;
}

// ─── V0.23.6 Known Schema (from investigation) ───────────────────────

// NOTE: These known schemas are hand-authored from manual investigation.
// They should be cross-checked against actual capture data when available.

// These represent what we know the v0.23.6 V1 API returned, codified as
// reference schemas for comparison.

const V023_KNOWN_SCHEMAS: Record<string, {
  description: string;
  fields: Record<string, { type: string; required: boolean; notes?: string }>;
}> = {
  'status': {
    description: 'GET /api/v1/status',
    fields: {
      'status': { type: 'string', required: true, notes: 'Value: "nominal"' },
      'locale': { type: 'string', required: true },
    }
  },
  'share': {
    description: 'POST /api/v1/share (create secret)',
    fields: {
      'custid':             { type: 'string', required: true },
      'metadata_key':       { type: 'string', required: true },
      'secret_key':         { type: 'string', required: true },
      'ttl':                { type: 'number', required: true, notes: 'Static TTL from creation' },
      'metadata_ttl':       { type: 'number', required: true, notes: 'Real seconds remaining' },
      'secret_ttl':         { type: 'number', required: true, notes: 'Real seconds remaining' },
      'state':              { type: 'string', required: true, notes: 'Value: "new"' },
      'updated':            { type: 'number', required: true, notes: 'Unix timestamp' },
      'created':            { type: 'number', required: true, notes: 'Unix timestamp' },
      'recipient':          { type: 'array',  required: false },
      'share_domain':       { type: 'string', required: false },
      'passphrase_required':{ type: 'boolean', required: true },
      'value':              { type: 'string', required: false, notes: 'Only for /generate' },
    }
  },
  'show_secret': {
    description: 'POST /api/v1/secret/:key',
    fields: {
      'value':        { type: 'string', required: true },
      'secret_key':   { type: 'string', required: true },
      'share_domain': { type: 'string', required: false },
    }
  },
  'show_metadata': {
    description: 'GET /api/v1/private/:key',
    fields: {
      'custid':             { type: 'string', required: true },
      'metadata_key':       { type: 'string', required: true },
      'secret_key':         { type: 'string', required: false, notes: 'Absent if received/burned' },
      'ttl':                { type: 'number', required: true },
      'metadata_ttl':       { type: 'number', required: true },
      'secret_ttl':         { type: 'number', required: true },
      'state':              { type: 'string', required: true, notes: 'new|viewed|received|burned|expired|orphaned' },
      'created':            { type: 'number', required: true },
      'updated':            { type: 'number', required: true },
      'received':           { type: 'number', required: false },
      'recipient':          { type: 'array',  required: false },
      'share_domain':       { type: 'string', required: false },
      'passphrase_required':{ type: 'boolean', required: true },
      'secret_realttl':     { type: 'number', required: false },
      'share_path':         { type: 'string', required: false },
      'share_url':          { type: 'string', required: false },
      'metadata_url':       { type: 'string', required: false },
      'burn_url':           { type: 'string', required: false },
    }
  },
  'error': {
    description: 'Error response',
    fields: {
      'message': { type: 'string', required: true },
      'shrimp':  { type: 'string', required: false, notes: 'CSRF token in v0.23.6' },
    }
  },
};

// ─── V0.24.0 Zod Schema Summary (from main branch investigation) ─────

// NOTE: These Zod schema summaries are manually maintained from the main branch.
// They should be cross-checked against the actual Zod source files when updated.

// Summarized from the Zod schemas in src/schemas/ on main branch.
// These represent the *declared* contract for the reconstituted V1.

const V024_ZOD_SCHEMAS: Record<string, {
  description: string;
  source_file: string;
  fields: Record<string, { type: string; required: boolean; notes?: string }>;
}> = {
  'status': {
    description: 'GET /api/v1/status',
    source_file: 'src/schemas/ (inferred from controllers)',
    fields: {
      'status': { type: 'string', required: true },
      'locale': { type: 'string', required: true },
    }
  },
  'share_receipt': {
    description: 'POST /api/v1/share (as receipt)',
    source_file: 'src/schemas/models/receipt.ts',
    fields: {
      'custid':              { type: 'string', required: true, notes: 'V3 uses "user_id"' },
      'identifier':          { type: 'string', required: true, notes: 'NEW - was metadata_key' },
      'key':                 { type: 'string', required: true },
      'shortid':             { type: 'string', required: true, notes: 'NEW field' },
      'secret_shortid':      { type: 'string', required: false, notes: 'NEW field' },
      'secret_identifier':   { type: 'string', required: false, notes: 'NEW field' },
      'metadata_key':        { type: 'string', required: false, notes: 'Possibly removed; check alias' },
      'secret_key':          { type: 'string', required: false, notes: 'Possibly removed; check alias' },
      'ttl':                 { type: 'number', required: false, notes: 'May be absent if using receipt_ttl' },
      'receipt_ttl':         { type: 'number', required: true, notes: 'NEW - was metadata_ttl' },
      'secret_ttl':          { type: 'number', required: true },
      'lifespan':            { type: 'number', required: true, notes: 'NEW field' },
      'state':               { type: 'string', required: true, notes: 'new|shared|received|revealed|burned|previewed|expired|orphaned' },
      'created':             { type: 'Date',   required: true, notes: 'Transform: seconds -> Date' },
      'updated':             { type: 'Date',   required: true, notes: 'Transform: seconds -> Date' },
      'recipients':          { type: 'array',  required: false, notes: 'Was "recipient" (singular)' },
      'share_domain':        { type: 'string', required: false },
      'has_passphrase':      { type: 'boolean', required: false, notes: 'Was "passphrase_required"' },
      'natural_expiration':  { type: 'string', required: true, notes: 'NEW field' },
      'expiration':          { type: 'Date',   required: true, notes: 'NEW field' },
      'share_path':          { type: 'string', required: true },
      'burn_path':           { type: 'string', required: true, notes: 'NEW name' },
      'receipt_path':        { type: 'string', required: true, notes: 'NEW - was metadata_url path' },
      'share_url':           { type: 'string', required: true },
      'receipt_url':         { type: 'string', required: true, notes: 'NEW - was metadata_url' },
      'burn_url':            { type: 'string', required: true },
      'is_viewed':           { type: 'boolean', required: true, notes: 'NEW boolean flags' },
      'is_received':         { type: 'boolean', required: true },
      'is_burned':           { type: 'boolean', required: true },
      'is_destroyed':        { type: 'boolean', required: true },
      'is_expired':          { type: 'boolean', required: true },
      'is_orphaned':         { type: 'boolean', required: true },
      'kind':                { type: 'string', required: false, notes: 'NEW: generate|conceal' },
      'memo':                { type: 'string', required: false, notes: 'NEW field' },
    }
  },
  'show_secret': {
    description: 'POST /api/v1/secret/:key (reveal)',
    source_file: 'src/schemas/models/secret.ts',
    fields: {
      'identifier':     { type: 'string', required: true, notes: 'NEW - was secret_key' },
      'key':            { type: 'string', required: true },
      'shortid':        { type: 'string', required: true, notes: 'NEW field' },
      'state':          { type: 'string', required: true, notes: 'new|received|revealed|burned|viewed|previewed' },
      'has_passphrase': { type: 'boolean', required: true, notes: 'Was implicit' },
      'verification':   { type: 'boolean', required: true, notes: 'NEW field' },
      'secret_value':   { type: 'string', required: false, notes: 'Was "value"' },
      'secret_ttl':     { type: 'number', required: true },
      'lifespan':       { type: 'number', required: true, notes: 'NEW field' },
    }
  },
};

// ─── Comparison Engine ────────────────────────────────────────────────

interface SchemaDiff {
  category: string;
  field: string;
  severity: 'breaking' | 'warning' | 'info';
  description: string;
}

function compareSchemas(
  v023: Record<string, { type: string; required: boolean; notes?: string }>,
  v024: Record<string, { type: string; required: boolean; notes?: string }>,
  endpointName: string
): SchemaDiff[] {
  const diffs: SchemaDiff[] = [];

  // Fields removed from v0.23.6
  for (const [field, spec] of Object.entries(v023)) {
    if (!(field in v024)) {
      diffs.push({
        category: endpointName,
        field,
        severity: spec.required ? 'breaking' : 'warning',
        description: `Field "${field}" present in v0.23.6 but absent in v0.24.0 schema${spec.required ? ' (REQUIRED)' : ' (optional)'}`,
      });
    }
  }

  // Fields added in v0.24.0
  for (const [field, spec] of Object.entries(v024)) {
    if (!(field in v023)) {
      diffs.push({
        category: endpointName,
        field,
        severity: spec.required ? 'warning' : 'info',
        description: `Field "${field}" added in v0.24.0${spec.required ? ' (required)' : ' (optional)'}${spec.notes ? ': ' + spec.notes : ''}`,
      });
    }
  }

  // Fields present in both but changed
  for (const [field, v023Spec] of Object.entries(v023)) {
    const v024Spec = v024[field];
    if (!v024Spec) continue;

    if (v023Spec.type !== v024Spec.type) {
      diffs.push({
        category: endpointName,
        field,
        severity: 'breaking',
        description: `Type changed: ${v023Spec.type} -> ${v024Spec.type}${v024Spec.notes ? ' (' + v024Spec.notes + ')' : ''}`,
      });
    }

    if (v023Spec.required && !v024Spec.required) {
      diffs.push({
        category: endpointName,
        field,
        severity: 'warning',
        description: `Was required in v0.23.6, now optional in v0.24.0`,
      });
    }
  }

  return diffs;
}

// ─── State Machine Comparison ─────────────────────────────────────────

function compareStateMachines(): SchemaDiff[] {
  const v023States = ['new', 'viewed', 'received', 'burned', 'expired', 'orphaned'];
  const v024States = ['new', 'shared', 'received', 'revealed', 'burned', 'previewed', 'expired', 'orphaned'];

  const diffs: SchemaDiff[] = [];

  const removed = v023States.filter(s => !v024States.includes(s));
  const added = v024States.filter(s => !v023States.includes(s));

  for (const state of removed) {
    diffs.push({
      category: 'state_machine',
      field: 'state',
      severity: 'breaking',
      description: `State "${state}" exists in v0.23.6 but not in v0.24.0. Clients matching on this value will break.`,
    });
  }

  for (const state of added) {
    diffs.push({
      category: 'state_machine',
      field: 'state',
      severity: 'warning',
      description: `State "${state}" is new in v0.24.0. Clients with exhaustive switch/case will need updating.`,
    });
  }

  // Semantic renames
  diffs.push({
    category: 'state_machine',
    field: 'state',
    severity: 'breaking',
    description: 'State rename: "viewed" -> "previewed". Both may coexist in v0.24 for backward compat; verify V1 sends old names.',
  });
  diffs.push({
    category: 'state_machine',
    field: 'state',
    severity: 'breaking',
    description: 'State rename: "received" -> "revealed". Check if V1 translates back to old terminology.',
  });

  return diffs;
}

// ─── Field Rename Tracking ────────────────────────────────────────────

function identifyRenames(): SchemaDiff[] {
  const renames: Array<{ old: string; new: string; context: string }> = [
    { old: 'metadata_key', new: 'identifier', context: 'Receipt/Metadata responses' },
    { old: 'secret_key', new: 'key or identifier', context: 'Secret responses' },
    { old: 'passphrase_required', new: 'has_passphrase', context: 'All secret-related responses' },
    { old: 'recipient', new: 'recipients', context: 'Receipt responses (singular -> plural)' },
    { old: 'metadata_ttl', new: 'receipt_ttl', context: 'TTL fields in receipt' },
    { old: 'metadata_url', new: 'receipt_url', context: 'URL fields in receipt' },
    { old: 'value', new: 'secret_value', context: 'Secret reveal response' },
  ];

  return renames.map(r => ({
    category: 'field_renames',
    field: r.old,
    severity: 'breaking' as const,
    description: `"${r.old}" renamed to "${r.new}" in ${r.context}. V1 must preserve old name for backward compat.`,
  }));
}

// ─── Main ─────────────────────────────────────────────────────────────

function main() {
  const capturesDir = process.argv[2];
  const outputFile = process.argv[3] || './diffs/schema-comparison.json';

  // Run static schema comparison regardless of captures
  const allDiffs: SchemaDiff[] = [];

  // Compare known schemas
  console.log('=== Schema Comparison: v0.23.6 vs v0.24.0 ===\n');

  // Status endpoint
  allDiffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.status.fields,
    V024_ZOD_SCHEMAS.status.fields,
    'GET /api/v1/status'
  ));

  // Share/create endpoint
  allDiffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.share.fields,
    V024_ZOD_SCHEMAS.share_receipt.fields,
    'POST /api/v1/share'
  ));

  // Show secret endpoint
  allDiffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.show_secret.fields,
    V024_ZOD_SCHEMAS.show_secret.fields,
    'POST /api/v1/secret/:key'
  ));

  // Show metadata endpoint
  allDiffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.show_metadata.fields,
    V024_ZOD_SCHEMAS.share_receipt.fields,  // Same schema applies
    'GET /api/v1/private/:key'
  ));

  // State machine
  allDiffs.push(...compareStateMachines());

  // Field renames
  allDiffs.push(...identifyRenames());

  // ── Process captures if provided ──

  let inferredSchemas: Record<string, InferredSchema> = {};

  if (capturesDir && existsSync(capturesDir)) {
    console.log(`\nProcessing captures from: ${capturesDir}\n`);

    const files = readdirSync(capturesDir).filter(f => f.endsWith('.json'));

    for (const file of files) {
      const capture: CaptureFile = JSON.parse(
        readFileSync(join(capturesDir, file), 'utf-8')
      );

      const endpointKey = `${capture.request.method} ${capture.request.path}`;

      if (!inferredSchemas[endpointKey]) {
        inferredSchemas[endpointKey] = {
          endpoint: capture.request.path,
          method: capture.request.method,
          status: capture.response.status,
          fields: {},
          sample_count: 0,
        };
      }

      const schema = inferredSchemas[endpointKey];
      schema.sample_count++;

      const bodyFields = inferSchemaFromBody(capture.response.body);
      for (const [fieldName, fieldInfo] of Object.entries(bodyFields)) {
        schema.fields[fieldName] = mergeFieldInfo(
          schema.fields[fieldName],
          fieldInfo.example,
          fieldName
        );
      }
    }

    console.log(`Inferred schemas for ${Object.keys(inferredSchemas).length} endpoint patterns`);
  }

  // ── Report ──

  const breaking = allDiffs.filter(d => d.severity === 'breaking');
  const warnings = allDiffs.filter(d => d.severity === 'warning');
  const info = allDiffs.filter(d => d.severity === 'info');

  console.log('\n--- Breaking Changes ---');
  for (const d of breaking) {
    console.log(`  [BREAK] ${d.category} :: ${d.field} — ${d.description}`);
  }

  console.log('\n--- Warnings ---');
  for (const d of warnings) {
    console.log(`  [WARN]  ${d.category} :: ${d.field} — ${d.description}`);
  }

  console.log('\n--- Info ---');
  for (const d of info) {
    console.log(`  [INFO]  ${d.category} :: ${d.field} — ${d.description}`);
  }

  console.log(`\nTotal: ${breaking.length} breaking, ${warnings.length} warnings, ${info.length} info`);

  // Write report
  const report = {
    generated: new Date().toISOString(),
    summary: {
      breaking: breaking.length,
      warnings: warnings.length,
      info: info.length,
    },
    diffs: allDiffs,
    inferred_schemas: inferredSchemas,
    known_schemas: {
      'v0.23.6': V023_KNOWN_SCHEMAS,
      'v0.24.0_zod': V024_ZOD_SCHEMAS,
    },
  };

  writeFileSync(outputFile, JSON.stringify(report, null, 2));
  console.log(`\nReport written to: ${outputFile}`);
}

main();
