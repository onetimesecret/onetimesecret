#!/usr/bin/env tsx
// src/scripts/openapi/schema-scanner.ts

/**
 * Schema Scanner
 *
 * Config-driven scanner that discovers SCHEMA constants in Ruby source files,
 * tracks module/class nesting to build fully-qualified class names (FQCN),
 * and cross-references against the TypeScript response schema registry and
 * Otto route handlers to produce a coverage gap report.
 *
 * Usage:
 *   pnpm run schema:scan
 */

import { readFileSync } from 'fs';
import { relative, join } from 'path';
import { globSync } from 'glob';
import { parseAllApiRoutes } from './otto-routes-parser';
import { responseSchemas } from '@/schemas/api/v3/responses';
import { modelSchemas } from '@/schemas/registry';

// =============================================================================
// Configuration
// =============================================================================

const SCAN_GLOBS = [
  'apps/api/**/logic/**/*.rb',
  'lib/onetime/models/*.rb',
];

const SCHEMA_PATTERN = /^\s*SCHEMAS?\s*=\s*(.+?)(?:\.freeze)?\s*$/m;

// =============================================================================
// Types
// =============================================================================

export interface SchemaEntry {
  className: string;     // e.g. "V3::Logic::Secrets::ConcealSecret"
  filePath: string;      // relative path to the .rb file
  schema: { model?: string; request?: string; response?: string };
}

export interface ScanResult {
  entries: SchemaEntry[];
  covered: SchemaEntry[];
  broken: SchemaEntry[];         // SCHEMA declared but key not in responseSchemas
  uncoveredHandlers: string[];   // from routes, no SCHEMA
  uncoveredModels: string[];     // model files scanned with no SCHEMA constant
}

// =============================================================================
// Ruby Value Parsing
// =============================================================================

/**
 * Parse a simplified Ruby string or hash literal value.
 *
 * Handles:
 * - String: 'models/secret' → { model: 'models/secret' }
 * - Hash: { response: 'concealData', request: 'concealSecret' }
 *
 * Singular SCHEMA = 'string' always means a model key. The convention
 * is: model keys use path-prefixed format ('models/secret'), response
 * and request keys use bare camelCase ('concealData', 'concealSecret').
 */
function parseRubyValue(raw: string): { model?: string; request?: string; response?: string } {
  const trimmed = raw.trim();

  // Single-quoted or double-quoted string → model key
  const strMatch = trimmed.match(/^['"](.+?)['"]$/);
  if (strMatch) {
    return { model: strMatch[1] };
  }

  // Hash literal: { key: 'value', ... }
  const hashMatch = trimmed.match(/^\{(.+)\}$/);
  if (hashMatch) {
    const inner = hashMatch[1];
    const result: { model?: string; request?: string; response?: string } = {};

    // Match model: 'value' or model: "value"
    const modelMatch = inner.match(/model:\s*['"](.+?)['"]/);
    if (modelMatch) {
      result.model = modelMatch[1];
    }

    // Match response: 'value' or response: "value"
    const responseMatch = inner.match(/response:\s*['"](.+?)['"]/);
    if (responseMatch) {
      result.response = responseMatch[1];
    }

    // Match request: 'value' or request: "value"
    const requestMatch = inner.match(/request:\s*['"](.+?)['"]/);
    if (requestMatch) {
      result.request = requestMatch[1];
    }

    return result;
  }

  // Fallback: treat as model key
  return { model: trimmed };
}

// =============================================================================
// Class Name Tracking
// =============================================================================

interface NestingFrame {
  segmentCount: number;
}

/**
 * Scan a Ruby file for module/class nesting and SCHEMA constants.
 *
 * Tracks a stack of nesting frames. Each module/class opening pushes
 * segments (split on ::), and each `end` pops the most recent frame.
 */
function scanRubyFile(filePath: string, projectRoot: string): SchemaEntry[] {
  const content = readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');
  const entries: SchemaEntry[] = [];

  const nameStack: string[] = [];
  const frameStack: NestingFrame[] = [];

  for (const line of lines) {
    const trimmed = line.trim();

    // Skip comments
    if (trimmed.startsWith('#')) continue;

    // Match module opening: `module V3::Logic` or `module Secrets`
    const moduleMatch = trimmed.match(/^module\s+([\w:]+)/);
    if (moduleMatch) {
      const segments = moduleMatch[1].split('::');
      nameStack.push(...segments);
      frameStack.push({ segmentCount: segments.length });
      continue;
    }

    // Match class opening: `class ConcealSecret < Base` or `class Secret`
    const classMatch = trimmed.match(/^class\s+([\w:]+)/);
    if (classMatch) {
      const segments = classMatch[1].split('::');
      nameStack.push(...segments);
      frameStack.push({ segmentCount: segments.length });
      continue;
    }

    // Track other block-introducing keywords (def, if, unless, while, until,
    // for, case, begin) with zero-segment frames so their `end` doesn't
    // incorrectly pop a module/class frame.
    // Only matches statement-form (start of line), not modifier-form.
    if (/^(def|if|unless|while|until|for|case|begin)\b/.test(trimmed)) {
      frameStack.push({ segmentCount: 0 });
      continue;
    }

    // Track do-blocks: `something.each do |x|`
    if (/\bdo\s*(\|[^|]*\|)?\s*$/.test(trimmed)) {
      frameStack.push({ segmentCount: 0 });
      // Don't continue — this line may also contain other meaningful content
    }

    // Match SCHEMA constant
    const schemaMatch = trimmed.match(SCHEMA_PATTERN);
    if (schemaMatch) {
      const fqcn = nameStack.join('::');
      entries.push({
        className: fqcn,
        filePath: relative(projectRoot, filePath),
        schema: parseRubyValue(schemaMatch[1]),
      });
      continue;
    }

    // Match `end` — pop the most recent nesting frame
    if (/^end\b/.test(trimmed)) {
      const frame = frameStack.pop();
      if (frame && frame.segmentCount > 0) {
        nameStack.splice(nameStack.length - frame.segmentCount, frame.segmentCount);
      }
    }
  }

  return entries;
}

// =============================================================================
// Handler Schema Map
// =============================================================================

/**
 * Build a map from handler class name to SchemaEntry.
 * Adds both FQCN entries and leaf-name entries for backward compat lookups.
 */
export function buildHandlerSchemaMap(entries: SchemaEntry[]): Map<string, SchemaEntry> {
  const map = new Map<string, SchemaEntry>();

  for (const entry of entries) {
    // Full qualified name
    map.set(entry.className, entry);

    // Leaf name (last segment after ::)
    const parts = entry.className.split('::');
    const leaf = parts[parts.length - 1];
    // Only set leaf if not already claimed (first-come wins)
    if (!map.has(leaf)) {
      map.set(leaf, entry);
    }
  }

  return map;
}

// =============================================================================
// Schema Validation
// =============================================================================

const validResponseKeys = new Set(Object.keys(responseSchemas));
const validModelKeys = new Set(Object.keys(modelSchemas));

// Request keys must match the generator's REQUEST_SCHEMA_REGISTRY.
// Defined here as a static set to avoid importing from the generator.
const validRequestKeys = new Set([
  'concealSecret',
  'generateSecret',
]);

/**
 * Check whether a schema key resolves to a known schema of the given type.
 */
function isValidKey(key: string, type: 'model' | 'response' | 'request'): boolean {
  if (type === 'model') return validModelKeys.has(key);
  if (type === 'request') return validRequestKeys.has(key);
  return validResponseKeys.has(key);
}

/**
 * Check whether all schema keys in an entry resolve to known schemas.
 * Each key type validates against its own registry.
 */
function isEntryCovered(entry: SchemaEntry): boolean {
  const { model, response, request } = entry.schema;
  if (model && !isValidKey(model, 'model')) return false;
  if (response && !isValidKey(response, 'response')) return false;
  if (request && !isValidKey(request, 'request')) return false;
  return true;
}

// =============================================================================
// Gap Discovery
// =============================================================================

/**
 * Find route handlers that have no SCHEMA constant declared.
 */
function findUncoveredHandlers(handlerMap: Map<string, SchemaEntry>): string[] {
  const allRoutes = parseAllApiRoutes();
  const routeHandlers = new Set<string>();

  for (const parsed of Object.values(allRoutes)) {
    for (const route of parsed.routes) {
      routeHandlers.add(route.handler);
    }
  }

  const uncovered: string[] = [];
  for (const handler of routeHandlers) {
    const leaf = handler.split('::').pop() ?? handler;
    if (!handlerMap.has(handler) && !handlerMap.has(leaf)) {
      uncovered.push(handler);
    }
  }

  return uncovered.sort();
}

/**
 * Find model files that have no SCHEMA constant declared.
 */
function findUncoveredModels(entries: SchemaEntry[], projectRoot: string): string[] {
  const modelGlob = 'lib/onetime/models/*.rb';
  const modelFiles = globSync(modelGlob, { cwd: projectRoot, absolute: true });
  const filesWithSchema = new Set(entries.map(e => join(projectRoot, e.filePath)));

  const uncovered: string[] = [];
  for (const modelFile of modelFiles) {
    if (!filesWithSchema.has(modelFile)) {
      const rel = relative(projectRoot, modelFile);
      uncovered.push(deriveModelName(rel));
    }
  }

  return uncovered.sort();
}

// =============================================================================
// Scanner
// =============================================================================

/**
 * Scan Ruby source files for SCHEMA constants and produce a coverage report.
 */
export function scanSchemas(globs?: string[]): ScanResult {
  const projectRoot = process.cwd();
  const patterns = globs ?? SCAN_GLOBS;

  // Discover Ruby files
  const allFiles = new Set<string>();
  for (const pattern of patterns) {
    const matches = globSync(pattern, { cwd: projectRoot, absolute: true });
    for (const f of matches) {
      allFiles.add(f);
    }
  }

  // Filter out spec files
  const rubyFiles = Array.from(allFiles).filter(f => {
    const rel = relative(projectRoot, f);
    return !rel.startsWith('spec/') && !rel.endsWith('_spec.rb') && !rel.includes('/spec/');
  });

  // Scan all files for SCHEMA constants
  const entries: SchemaEntry[] = [];
  for (const file of rubyFiles) {
    entries.push(...scanRubyFile(file, projectRoot));
  }

  // Classify entries
  const covered: SchemaEntry[] = [];
  const broken: SchemaEntry[] = [];

  for (const entry of entries) {
    if (isEntryCovered(entry)) {
      covered.push(entry);
    } else {
      broken.push(entry);
    }
  }

  const handlerMap = buildHandlerSchemaMap(entries);
  const uncoveredHandlers = findUncoveredHandlers(handlerMap);
  const uncoveredModels = findUncoveredModels(entries, projectRoot);

  return { entries, covered, broken, uncoveredHandlers, uncoveredModels };
}

/**
 * Derive a display name for a model file.
 * e.g. "lib/onetime/models/custom_domain.rb" → "Onetime::CustomDomain"
 */
function deriveModelName(relPath: string): string {
  const basename = relPath.split('/').pop()?.replace('.rb', '') ?? relPath;
  const pascal = basename
    .split('_')
    .map(s => s.charAt(0).toUpperCase() + s.slice(1))
    .join('');
  return `Onetime::${pascal}`;
}

// =============================================================================
// CLI Gap Report
// =============================================================================

function formatSchemaValue(schema: SchemaEntry['schema']): string {
  const parts: string[] = [];
  if (schema.model) parts.push(`model:${schema.model}`);
  if (schema.response) parts.push(`response:${schema.response}`);
  if (schema.request) parts.push(`request:${schema.request}`);
  return parts.join(' + ');
}

/**
 * Describe which key type(s) failed validation in a broken entry.
 */
function describeBrokenKey(schema: SchemaEntry['schema']): string {
  const broken: string[] = [];
  if (schema.model && !isValidKey(schema.model, 'model')) broken.push('model');
  if (schema.response && !isValidKey(schema.response, 'response')) broken.push('response');
  if (schema.request && !isValidKey(schema.request, 'request')) broken.push('request');
  return broken.length > 0 ? `invalid ${broken.join(', ')} key` : 'unknown';
}

function printReport(result: ScanResult): void {
  console.log('Schema Scanner Report');
  console.log('═════════════════════════════════════════\n');

  // Covered entries
  if (result.covered.length > 0) {
    for (const entry of result.covered) {
      console.log(`COVERED: ${entry.className} → ${formatSchemaValue(entry.schema)}`);
    }
    console.log('');
  }

  // Broken entries — identify which key type failed
  if (result.broken.length > 0) {
    for (const entry of result.broken) {
      const detail = describeBrokenKey(entry.schema);
      console.log(`BROKEN: ${entry.className} → ${formatSchemaValue(entry.schema)} (${detail})`);
    }
    console.log('');
  }

  // Uncovered handlers
  if (result.uncoveredHandlers.length > 0) {
    for (const handler of result.uncoveredHandlers) {
      console.log(`UNCOVERED HANDLER: ${handler} (no SCHEMA)`);
    }
    console.log('');
  }

  // Uncovered models
  if (result.uncoveredModels.length > 0) {
    for (const model of result.uncoveredModels) {
      console.log(`UNCOVERED MODEL: ${model} (no SCHEMA)`);
    }
    console.log('');
  }

  // Summary
  const totalHandlers = result.uncoveredHandlers.length + result.entries.length;
  const totalModels = result.uncoveredModels.length +
    result.entries.filter(e => e.filePath.startsWith('lib/onetime/models/')).length;

  console.log('Summary');
  console.log('───────────────────────');
  console.log(`Handlers with SCHEMA:  ${result.entries.length}/${totalHandlers}`);
  console.log(`Models with SCHEMA:    ${totalModels - result.uncoveredModels.length}/${totalModels}`);
  console.log(`Covered (valid keys):  ${result.covered.length}`);
  console.log(`Broken (invalid keys): ${result.broken.length}`);
  console.log(`Uncovered handlers:    ${result.uncoveredHandlers.length}`);
  console.log(`Uncovered models:      ${result.uncoveredModels.length}`);
}

// =============================================================================
// Main (when run as script)
// =============================================================================

// Detect if this file is being run directly (ESM entry point detection)
const isMainModule = process.argv[1]?.endsWith('schema-scanner.ts') ||
  process.argv[1]?.endsWith('schema-scanner.js');

if (isMainModule) {
  const result = scanSchemas();
  printReport(result);
}
