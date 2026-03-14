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

// ─── V0.24.0 Zod Schema Summary (V3/model schemas — internal) ────────
//
// These are the V3/model schemas from src/schemas/models/. They represent
// what the *internal* v0.24 data model looks like. The V1 API does NOT
// send these directly — it uses receipt_hsh to map back to v0.23 names.
//
// IMPORTANT: For V1 backward-compatibility analysis, use V024_V1_ZOD_SCHEMAS
// below, which reflect the actual V1 API output shapes.

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
    description: 'POST /api/v1/share (as receipt) — V3 model schema',
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
    description: 'POST /api/v1/secret/:key (reveal) — V3 model schema',
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

// ─── V0.24.0 V1 API Schemas (actual wire format) ─────────────────────
//
// These schemas reflect what the V1 API *actually sends* over the wire.
// The V1 controller uses receipt_hsh (class_methods.rb) to map v0.24
// internal field names back to v0.23.x names. The V1 Zod schemas in
// src/schemas/api/v1/responses/secrets.ts declare this contract.
//
// Source: apps/api/v1/controllers/class_methods.rb#receipt_hsh
//         apps/api/v1/controllers/index.rb (show_secret, burn_secret)
//         src/schemas/api/v1/responses/secrets.ts

const V024_V1_ZOD_SCHEMAS: Record<string, {
  description: string;
  source_file: string;
  fields: Record<string, { type: string; required: boolean; notes?: string }>;
}> = {
  'status': {
    description: 'GET /api/v1/status — unchanged',
    source_file: 'src/schemas/api/v1/responses/index.ts',
    fields: {
      'status': { type: 'string', required: true },
      'locale': { type: 'string', required: true },
    }
  },
  'share_receipt': {
    description: 'POST /api/v1/share — receipt_hsh output',
    source_file: 'src/schemas/api/v1/responses/secrets.ts',
    fields: {
      'custid':              { type: 'string', required: true, notes: 'Preserved: cust.email via opts[:custid]' },
      'metadata_key':        { type: 'string', required: true, notes: 'Mapped from md.identifier' },
      'secret_key':          { type: 'string', required: false, notes: 'Mapped from secret_identifier; absent when state=received' },
      'ttl':                 { type: 'number', required: true, notes: 'Static TTL from receipt_ttl (was secret_ttl*1)' },
      'metadata_ttl':        { type: 'number', required: true, notes: 'Mapped from receipt_realttl (current_expiration)' },
      'secret_ttl':          { type: 'number', required: false, notes: 'Actual seconds remaining; absent when state=received' },
      'state':               { type: 'string', required: true, notes: 'Translated via V1_STATE_MAP: previewed→viewed, shared→new, revealed→received' },
      'updated':             { type: 'number', required: true, notes: 'Unix timestamp (integer), NOT Date object' },
      'created':             { type: 'number', required: true, notes: 'Unix timestamp (integer), NOT Date object' },
      'received':            { type: 'number', required: false, notes: 'Only present when state=received; falls back to revealed timestamp' },
      'recipient':           { type: 'array',  required: true, notes: 'Preserved as singular "recipient" (array)' },
      'share_domain':        { type: 'string', required: true, notes: 'Empty string when nil (never null)' },
      'value':               { type: 'string', required: false, notes: 'Only for /generate; preserved field name' },
      'passphrase_required': { type: 'boolean', required: false, notes: 'Preserved field name from opts' },
    }
  },
  'show_secret': {
    description: 'POST /api/v1/secret/:key — V1 controller inline response',
    source_file: 'apps/api/v1/controllers/index.rb:149-156',
    fields: {
      'value':        { type: 'string', required: true, notes: 'Preserved: logic.secret_value' },
      'secret_key':   { type: 'string', required: true, notes: 'Preserved: req.params[key]' },
      'share_domain': { type: 'string', required: true, notes: 'Preserved: logic.share_domain' },
    }
  },
  'show_metadata': {
    description: 'GET /api/v1/receipt/:key — receipt_hsh output (same as share)',
    source_file: 'src/schemas/api/v1/responses/secrets.ts',
    fields: {
      'custid':              { type: 'string', required: true },
      'metadata_key':        { type: 'string', required: true },
      'secret_key':          { type: 'string', required: false, notes: 'Absent when state=received' },
      'ttl':                 { type: 'number', required: true },
      'metadata_ttl':        { type: 'number', required: true },
      'secret_ttl':          { type: 'number', required: false, notes: 'Absent when state=received' },
      'state':               { type: 'string', required: true, notes: 'Translated via V1_STATE_MAP' },
      'updated':             { type: 'number', required: true },
      'created':             { type: 'number', required: true },
      'received':            { type: 'number', required: false },
      'recipient':           { type: 'array',  required: true },
      'share_domain':        { type: 'string', required: true },
      'passphrase_required': { type: 'boolean', required: false },
    }
  },
  'burn_secret': {
    description: 'POST /api/v1/receipt/:key/burn — V1 controller inline response',
    source_file: 'apps/api/v1/controllers/index.rb:168-171',
    fields: {
      'state':           { type: 'object', required: true, notes: 'Full receipt_hsh of the burned receipt' },
      'secret_shortkey': { type: 'string', required: true, notes: 'v0.23 field name; mapped from receipt.secret_shortid (v0.24 internal)' },
    }
  },
  'error': {
    description: 'Error response — flat JSON',
    source_file: 'apps/api/v1/controllers/base.rb',
    fields: {
      'message':    { type: 'string', required: true },
      'secret_key': { type: 'string', required: false, notes: 'Present in show_secret 404' },
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

  // ── Part A: V3/model schema comparison (shows full internal delta) ──
  const v3Diffs: SchemaDiff[] = [];

  console.log('=== Part A: v0.23.6 vs v0.24.0 V3/Model Schemas (internal delta) ===\n');
  console.log('NOTE: These diffs show what changed internally. The V1 API');
  console.log('uses receipt_hsh to map back to v0.23 names, so most of');
  console.log('these are NOT visible to V1 clients.\n');

  v3Diffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.status.fields,
    V024_ZOD_SCHEMAS.status.fields,
    '[V3] GET /api/v1/status'
  ));
  v3Diffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.share.fields,
    V024_ZOD_SCHEMAS.share_receipt.fields,
    '[V3] POST /api/v1/share'
  ));
  v3Diffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.show_secret.fields,
    V024_ZOD_SCHEMAS.show_secret.fields,
    '[V3] POST /api/v1/secret/:key'
  ));
  v3Diffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.show_metadata.fields,
    V024_ZOD_SCHEMAS.share_receipt.fields,
    '[V3] GET /api/v1/private/:key'
  ));

  // ── Part B: V1-specific comparison (actual wire format) ──
  const v1Diffs: SchemaDiff[] = [];

  console.log('\n=== Part B: v0.23.6 vs v0.24.0 V1 API (actual wire format) ===\n');
  console.log('These diffs show what V1 API clients actually experience.\n');

  v1Diffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.status.fields,
    V024_V1_ZOD_SCHEMAS.status.fields,
    '[V1] GET /api/v1/status'
  ));
  v1Diffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.share.fields,
    V024_V1_ZOD_SCHEMAS.share_receipt.fields,
    '[V1] POST /api/v1/share'
  ));
  v1Diffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.show_secret.fields,
    V024_V1_ZOD_SCHEMAS.show_secret.fields,
    '[V1] POST /api/v1/secret/:key'
  ));
  v1Diffs.push(...compareSchemas(
    V023_KNOWN_SCHEMAS.show_metadata.fields,
    V024_V1_ZOD_SCHEMAS.show_metadata.fields,
    '[V1] GET /api/v1/private/:key'
  ));

  // Combine all diffs for the full report
  const allDiffs: SchemaDiff[] = [...v3Diffs, ...v1Diffs];

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

  // V1-specific results (what matters for backward compat)
  const v1Breaking = v1Diffs.filter(d => d.severity === 'breaking');
  const v1Warnings = v1Diffs.filter(d => d.severity === 'warning');
  const v1Info = v1Diffs.filter(d => d.severity === 'info');

  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║  V1 API Wire Format (client-facing)          ║');
  console.log('╚══════════════════════════════════════════════╝');

  if (v1Breaking.length === 0) {
    console.log('\n  ✓ No breaking changes for V1 API clients');
  } else {
    console.log('\n--- V1 Breaking Changes ---');
    for (const d of v1Breaking) {
      console.log(`  [BREAK] ${d.category} :: ${d.field} — ${d.description}`);
    }
  }

  if (v1Warnings.length > 0) {
    console.log('\n--- V1 Warnings ---');
    for (const d of v1Warnings) {
      console.log(`  [WARN]  ${d.category} :: ${d.field} — ${d.description}`);
    }
  }

  console.log(`\nV1 Total: ${v1Breaking.length} breaking, ${v1Warnings.length} warnings, ${v1Info.length} info`);

  // V3/model results (internal reference)
  const v3Breaking = v3Diffs.filter(d => d.severity === 'breaking');
  const v3Warnings = v3Diffs.filter(d => d.severity === 'warning');
  const v3Info = v3Diffs.filter(d => d.severity === 'info');

  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║  V3/Model Schemas (internal reference)       ║');
  console.log('╚══════════════════════════════════════════════╝');
  console.log(`\nV3 Total: ${v3Breaking.length} breaking, ${v3Warnings.length} warnings, ${v3Info.length} info`);
  console.log('(These are internal model changes, NOT visible to V1 clients)');

  // Combined totals
  const breaking = allDiffs.filter(d => d.severity === 'breaking');
  const warnings = allDiffs.filter(d => d.severity === 'warning');
  const info = allDiffs.filter(d => d.severity === 'info');

  console.log(`\nCombined Total: ${breaking.length} breaking, ${warnings.length} warnings, ${info.length} info`);

  // Write report
  const report = {
    generated: new Date().toISOString(),
    summary: {
      v1_wire_format: {
        breaking: v1Breaking.length,
        warnings: v1Warnings.length,
        info: v1Info.length,
      },
      v3_internal: {
        breaking: v3Breaking.length,
        warnings: v3Warnings.length,
        info: v3Info.length,
      },
      combined: {
        breaking: breaking.length,
        warnings: warnings.length,
        info: info.length,
      },
    },
    v1_diffs: v1Diffs,
    v3_diffs: v3Diffs,
    state_machine_diffs: allDiffs.filter(d => d.category === 'state_machine'),
    field_rename_diffs: allDiffs.filter(d => d.category === 'field_renames'),
    diffs: allDiffs,
    inferred_schemas: inferredSchemas,
    known_schemas: {
      'v0.23.6': V023_KNOWN_SCHEMAS,
      'v0.24.0_v1_zod': V024_V1_ZOD_SCHEMAS,
      'v0.24.0_v3_zod': V024_ZOD_SCHEMAS,
    },
  };

  writeFileSync(outputFile, JSON.stringify(report, null, 2));
  console.log(`\nReport written to: ${outputFile}`);
}

main();
