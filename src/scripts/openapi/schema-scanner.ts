#!/usr/bin/env tsx
// src/scripts/openapi/schema-scanner.ts

/**
 * Schema Scanner (Prism-based)
 *
 * Uses the official Ruby parser (@ruby/prism) to discover SCHEMA constants
 * in Ruby source files, resolve module/class scope via AST traversal, and
 * cross-reference against the TypeScript response schema registry and Otto
 * route handlers to produce a coverage gap report.
 *
 * Supports three SCHEMA value forms:
 *
 *   1. String:      SCHEMA  = 'models/secret'
 *                   → { model: 'models/secret' }
 *
 *   2. Flat hash:   SCHEMAS = { response: 'concealData', request: 'concealSecret' }
 *                   → single entry: { response: 'concealData', request: 'concealSecret' }
 *
 *   3. Method-keyed hash:
 *                   SCHEMAS = {
 *                     system_status: { response: 'systemStatus' },
 *                     system_version: { response: 'systemVersion' },
 *                   }
 *                   → one entry per method: FQCN.method_name → { response: '...' }
 *
 * Usage:
 *   pnpm run schemas:scan
 */

import { readFileSync } from 'fs';
import { relative, join } from 'path';
import { globSync } from 'glob';
import { loadPrism, Visitor } from '@ruby/prism';
// Node types are checked via constructor.name at runtime (Prism's JS API
// uses plain classes without a shared type hierarchy we can import).
// The visitor callbacks receive untyped nodes — see @ruby/prism's nodes.js.
import { parseAllApiRoutes } from './otto-routes-parser';
import { responseSchemas as v1ResponseSchemas } from '@/schemas/api/v1/responses/registry';
import { responseSchemas as v2ResponseSchemas } from '@/schemas/api/v2/responses/registry';
import { responseSchemas as v3ResponseSchemas } from '@/schemas/api/v3/responses/registry';
import { responseSchemas as internalResponseSchemas } from '@/schemas/api/internal/responses/registry';
import { modelSchemas } from '@/schemas/registry';

// Version-aware registry selection for schema validation.
// Each API version validates against its own registry, eliminating the need
// to spread V1 schemas into V3 just to satisfy a monolithic validator.
type ResponseSchemaRegistry =
  | typeof v1ResponseSchemas
  | typeof v2ResponseSchemas
  | typeof v3ResponseSchemas
  | typeof internalResponseSchemas;

const registryByVersion: Record<string, ResponseSchemaRegistry> = {
  v1: v1ResponseSchemas,
  v2: v2ResponseSchemas,
  v3: v3ResponseSchemas,
  internal: internalResponseSchemas,
};

// Internal API prefixes that map to the internal registry
const INTERNAL_API_PREFIXES = ['AccountAPI', 'ColonelAPI', 'DomainsAPI', 'OrganizationAPI', 'InviteAPI'];

/**
 * Extract API version from a Ruby class name.
 * "V3::Logic::Secrets::ConcealSecret" → "v3"
 * "ColonelAPI::Logic::Colonel::GetColonelInfo" → "internal"
 * "Onetime::CustomDomain" → null (model, no version prefix)
 */
function extractVersion(className: string): string | null {
  // Check for versioned APIs (V1, V2, V3)
  const versionMatch = className.match(/^(V\d+)::/i);
  if (versionMatch) return versionMatch[1].toLowerCase();

  // Check for internal API prefixes
  const prefix = className.split('::')[0];
  if (INTERNAL_API_PREFIXES.includes(prefix)) return 'internal';

  return null;
}

/**
 * Get the response schema registry for a given version.
 * Falls back to v3 for unknown versions (models, etc.)
 */
function getRegistryForVersion(version: string | null): ResponseSchemaRegistry {
  return version ? (registryByVersion[version] ?? v3ResponseSchemas) : v3ResponseSchemas;
}

// =============================================================================
// Configuration
// =============================================================================

const SCAN_GLOBS = [
  'apps/api/**/logic/**/*.rb',
  'apps/api/**/controllers/**/*.rb',
  'lib/onetime/models/*.rb',
];

// =============================================================================
// Types
// =============================================================================

export interface SchemaEntry {
  className: string;     // e.g. "V3::Logic::Secrets::ConcealSecret" or "V3::Logic::Meta.system_status"
  filePath: string;      // relative path to the .rb file
  schema: { model?: string; request?: string; response?: string };
  description?: string;  // @api tag description from class/module comments
}

export interface ScanResult {
  entries: SchemaEntry[];
  covered: SchemaEntry[];
  broken: SchemaEntry[];         // SCHEMA declared but key not in responseSchemas
  uncoveredHandlers: string[];   // from routes, no SCHEMA
  uncoveredModels: string[];     // model files scanned with no SCHEMA constant
}

// =============================================================================
// AST Value Extraction
// =============================================================================

/**
 * Unwrap a `.freeze` call to get the underlying value node.
 * If the node is `{ ... }.freeze`, returns the HashNode receiver.
 * Otherwise returns the node as-is.
 */
function unwrapFreeze(node: any): any {
  if (node.constructor.name === 'CallNode' && node.name === 'freeze' && node.receiver) {
    return node.receiver;
  }
  return node;
}

/**
 * Extract a string value from a StringNode or SymbolNode.
 */
function extractStringValue(node: any): string | null {
  if (node.constructor.name === 'StringNode' || node.constructor.name === 'SymbolNode') {
    return node.unescaped?.value ?? null;
  }
  return null;
}

/**
 * Extract a flat schema hash from a HashNode.
 * Expects: { response: 'foo', request: 'bar', model: 'baz' }
 * where all values are strings.
 */
function extractFlatSchema(hash: any): { model?: string; request?: string; response?: string } {
  const result: { model?: string; request?: string; response?: string } = {};
  for (const element of hash.elements) {
    if (element.constructor.name !== 'AssocNode') continue;
    const key = extractStringValue(element.key);
    const value = extractStringValue(element.value);
    if (key && value) {
      if (key === 'model' || key === 'response' || key === 'request') {
        result[key] = value;
      }
    }
  }
  return result;
}

/**
 * Determine if a HashNode contains method-keyed schemas (nested hashes)
 * vs flat schema keys (string values).
 *
 * Method-keyed: { system_status: { response: 'systemStatus' }, ... }
 * Flat:         { response: 'concealData', request: 'concealSecret' }
 *
 * Detection: if any value is a HashNode, it's method-keyed.
 */
function isMethodKeyed(hash: any): boolean {
  for (const element of hash.elements) {
    if (element.constructor.name !== 'AssocNode') continue;
    const value = unwrapFreeze(element.value);
    if (value.constructor.name === 'HashNode') return true;
  }
  return false;
}

/**
 * Extract method-keyed schemas from a nested HashNode.
 * Returns an array of [methodName, schema] tuples.
 */
function extractMethodKeyedSchemas(
  hash: any,
): Array<[string, { model?: string; request?: string; response?: string }]> {
  const results: Array<[string, { model?: string; request?: string; response?: string }]> = [];
  for (const element of hash.elements) {
    if (element.constructor.name !== 'AssocNode') continue;
    const methodName = extractStringValue(element.key);
    const innerValue = unwrapFreeze(element.value);
    if (methodName && innerValue.constructor.name === 'HashNode') {
      results.push([methodName, extractFlatSchema(innerValue)]);
    }
  }
  return results;
}

// =============================================================================
// AST Scope Resolution
// =============================================================================

/**
 * Resolve the full constant name from a constantPath node.
 *
 * Handles both simple and qualified module/class declarations:
 *   module Foo          → ConstantReadNode("Foo")      → ["Foo"]
 *   module Foo::Bar     → ConstantPathNode(parent, "Bar") → ["Foo", "Bar"]
 *   module A::B::C      → nested ConstantPathNodes       → ["A", "B", "C"]
 */
function resolveConstantPath(node: any): string[] {
  const typeName = node.constructor.name;
  if (typeName === 'ConstantReadNode') {
    return [node.name];
  }
  if (typeName === 'ConstantPathNode') {
    const parentSegments = node.parent ? resolveConstantPath(node.parent) : [];
    return [...parentSegments, node.name];
  }
  return [];
}

// =============================================================================
// AST Visitor — Schema Discovery
// =============================================================================

/**
 * Visitor that walks a Ruby AST to find SCHEMA/SCHEMAS constant assignments,
 * tracking module/class nesting to build fully-qualified class names.
 */
class SchemaVisitor extends Visitor {
  private scope: string[] = [];
  public entries: SchemaEntry[] = [];
  private filePath: string;
  private comments: any[];
  private source: string;
  private descriptionStack: (string | undefined)[] = [];

  constructor(filePath: string, comments: any[] = [], source: string = '') {
    super();
    this.filePath = filePath;
    this.comments = comments;
    this.source = source;
  }

  override visitModuleNode(node: any): void {
    const segments = resolveConstantPath(node.constantPath);
    const description = this.findApiDescription(node);
    this.descriptionStack.push(description);
    this.scope.push(...segments);
    super.visitModuleNode(node);
    this.scope.splice(this.scope.length - segments.length, segments.length);
    this.descriptionStack.pop();
  }

  override visitClassNode(node: any): void {
    const segments = resolveConstantPath(node.constantPath);
    const description = this.findApiDescription(node);
    this.descriptionStack.push(description);
    this.scope.push(...segments);
    super.visitClassNode(node);
    this.scope.splice(this.scope.length - segments.length, segments.length);
    this.descriptionStack.pop();
  }

  override visitConstantWriteNode(node: any): void {
    if (node.name === 'SCHEMA' || node.name === 'SCHEMAS') {
      this.processSchemaConstant(node);
    }
    super.visitConstantWriteNode(node);
  }

  private processSchemaConstant(node: any): void {
    const fqcn = this.scope.join('::');
    const value = unwrapFreeze(node.value);
    const nodeName = value.constructor.name;
    const description = this.descriptionStack[this.descriptionStack.length - 1];

    // Form 1: SCHEMA = 'models/secret'
    if (nodeName === 'StringNode') {
      const str = extractStringValue(value);
      if (str) {
        this.entries.push({
          className: fqcn,
          filePath: this.filePath,
          schema: { model: str },
          ...(description && { description }),
        });
      }
      return;
    }

    // Form 2 or 3: SCHEMAS = { ... }
    if (nodeName === 'HashNode') {
      if (isMethodKeyed(value)) {
        // Form 3: method-keyed — emit one entry per method
        const methods = extractMethodKeyedSchemas(value);
        for (const [methodName, schema] of methods) {
          this.entries.push({
            className: `${fqcn}.${methodName}`,
            filePath: this.filePath,
            schema,
            ...(description && { description }),
          });
        }
      } else {
        // Form 2: flat hash — single entry
        this.entries.push({
          className: fqcn,
          filePath: this.filePath,
          schema: extractFlatSchema(value),
          ...(description && { description }),
        });
      }
    }
  }

  /**
   * Find the @api description from comments preceding a class/module node.
   * Uses Prism's flat comment array, correlating by byte offset.
   */
  private findApiDescription(node: any): string | undefined {
    if (this.comments.length === 0) return undefined;

    const nodeStart = node.location.startOffset;

    // Find comments preceding this node, nearest first
    const preceding = this.comments
      .filter((c: any) => c.location.startOffset + c.location.length <= nodeStart)
      .sort((a: any, b: any) => b.location.startOffset - a.location.startOffset);

    if (preceding.length === 0) return undefined;

    // Collect the contiguous comment block immediately before the node
    const block: string[] = [];
    let expectedBefore = nodeStart;

    for (const comment of preceding) {
      const commentEnd = comment.location.startOffset + comment.location.length;
      const gap = this.source.slice(commentEnd, expectedBefore);
      // Allow only single-newline gaps (with optional leading spaces on the same line).
      // A blank line (two consecutive newlines) breaks the association — in Ruby
      // convention, a blank line between a comment and a class means the comment
      // is not documenting that class.
      if (!/^\s*$/.test(gap) || /\n\s*\n/.test(gap)) break;

      const text = this.source.slice(comment.location.startOffset, commentEnd);
      block.unshift(text);
      expectedBefore = comment.location.startOffset;
    }

    return this.parseApiTag(block);
  }

  /**
   * Parse a block of comment lines for an @api tag.
   * Joins continuation lines (indented by 2+ spaces) into the description.
   *
   * Example input:
   *   ["# Conceal a secret", "#", "# @api Store a secret value.",
   *    "#   The secret is encrypted at rest."]
   * → "Store a secret value. The secret is encrypted at rest."
   */
  private parseApiTag(commentLines: string[]): string | undefined {
    let description: string | undefined;
    let collecting = false;

    for (const line of commentLines) {
      // Strip leading # and optional single space
      const stripped = line.replace(/^#\s?/, '');

      if (stripped.startsWith('@api ')) {
        collecting = true;
        description = stripped.slice(5).trim();
      } else if (collecting && /^\s{2,}/.test(stripped)) {
        // Continuation line (indented by 2+ spaces after #)
        const continuation = stripped.trim();
        description = description ? description + ' ' + continuation : continuation;
      } else if (collecting) {
        collecting = false;
      }
    }

    return description || undefined;
  }
}

// =============================================================================
// File Scanner
// =============================================================================

type ParseFn = (source: string) => any;

/**
 * Scan a Ruby file for SCHEMA constants using the Prism parser.
 */
function scanRubyFile(filePath: string, projectRoot: string, parse: ParseFn): SchemaEntry[] {
  const content = readFileSync(filePath, 'utf-8');
  const relPath = relative(projectRoot, filePath);

  const result = parse(content);
  const visitor = new SchemaVisitor(relPath, result.comments ?? [], content);
  visitor.visit(result.value);

  return visitor.entries;
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
    // Full qualified name (includes method-keyed like "V3::Logic::Meta.system_status")
    map.set(entry.className, entry);

    // Leaf name (last segment after :: or .)
    // For "V3::Logic::Meta.system_status" → "Meta.system_status"
    // For "V3::Logic::Secrets::ConcealSecret" → "ConcealSecret"
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

const validModelKeys = new Set(Object.keys(modelSchemas));

// Request keys must match the generator's REQUEST_SCHEMA_REGISTRY.
// Defined here as a static set to avoid importing from the generator.
const validRequestKeys = new Set([
  'burnSecret',
  'concealSecret',
  'createIncomingSecret',
  'generateSecret',
  'listSecretStatus',
  'receiveFeedback',
  'revealSecret',
  'showMultipleReceipts',
  'updateReceipt',
  'validateRecipient',
]);

/**
 * Check whether a schema key resolves to a known schema of the given type.
 * For response schemas, validates against the version-appropriate registry.
 */
function isValidKey(
  key: string,
  type: 'model' | 'response' | 'request',
  version?: string | null
): boolean {
  if (type === 'model') return validModelKeys.has(key);
  if (type === 'request') return validRequestKeys.has(key);
  // Response validation: use version-specific registry
  const registry = getRegistryForVersion(version ?? null);
  return Object.hasOwn(registry, key);
}

/**
 * Check whether all schema keys in an entry resolve to known schemas.
 * Response keys validate against the registry matching the entry's API version.
 */
function isEntryCovered(entry: SchemaEntry): boolean {
  const { model, response, request } = entry.schema;
  const version = extractVersion(entry.className);
  if (model && !isValidKey(model, 'model')) return false;
  if (response && !isValidKey(response, 'response', version)) return false;
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
    // Normalize instance-method syntax (#) to module-method syntax (.)
    // so that V1::Controllers::Index#status matches Index.status in the map
    const normalized = handler.replace('#', '.');
    const leaf = normalized.split('::').pop() ?? normalized;
    if (!handlerMap.has(normalized) && !handlerMap.has(leaf)) {
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
 * Async because Prism's WASM module requires async initialization.
 */
export async function scanSchemas(globs?: string[]): Promise<ScanResult> {
  const projectRoot = process.cwd();
  const patterns = globs ?? SCAN_GLOBS;

  // Initialize the Prism parser (loads WASM once)
  const parse = await loadPrism();

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
    entries.push(...scanRubyFile(file, projectRoot, parse));
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
  const result = await scanSchemas();
  printReport(result);
}
