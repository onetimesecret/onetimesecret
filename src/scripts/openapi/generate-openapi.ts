#!/usr/bin/env tsx
// src/scripts/openapi/generate-openapi.ts

/**
 * Convention-Based OpenAPI 3.1 Generator
 *
 * Generates a complete OpenAPI spec from Otto routes.txt metadata and
 * Zod v4 schemas. No third-party OpenAPI libraries required.
 *
 * How it works:
 * 1. Parses all apps/api/{name}/routes.txt via otto-routes-parser
 * 2. Derives operationId, summary, and tags from handler class names
 * 3. Resolves request/response schemas from the registry via z.toJSONSchema()
 * 4. Emits OpenAPI 3.1 JSON (uses JSON Schema 2020-12 natively)
 *
 * Usage:
 *   pnpm run openapi:generate                # Generate spec
 *   pnpm run openapi:generate -- --dry-run   # Preview without writing
 *   pnpm run openapi:generate -- --verbose    # Show per-route details
 *   pnpm run openapi:generate -- --no-tags    # Omit OpenAPI tags from operations
 *   pnpm run openapi:generate -- --sort path  # Sort paths lexicographically
 *   pnpm run openapi:generate -- --sort method # Sort methods per REST convention
 *   pnpm run openapi:generate -- --sort path,method  # Both
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { z } from 'zod';

import {
  getAuthRequirements,
  getContentType,
  getPathParams,
  getResponseType,
  parseAllApiRoutes,
  toOpenAPIPath,
  type OttoRoute,
} from './otto-routes-parser';

import { standardErrorResponses, type SpecTarget } from './route-config';
import {
  buildHandlerSchemaMap,
  scanSchemas,
  type ScanResult,
  type SchemaEntry,
} from './schema-scanner';

import {
  burnSecretRequestSchema,
  concealSecretRequestSchema,
  createIncomingSecretRequestSchema,
  generateSecretRequestSchema,
  listSecretStatusRequestSchema,
  receiveFeedbackRequestSchema,
  revealSecretRequestSchema,
  showMultipleReceiptsRequestSchema,
  updateReceiptRequestSchema,
  validateRecipientRequestSchema,
} from '@/schemas/api/v3/requests';
import { responseSchemas as v1ResponseSchemas } from '@/schemas/api/v1/responses/registry';
import { responseSchemas as v2ResponseSchemas } from '@/schemas/api/v2/responses/registry';
import { responseSchemas as v3ResponseSchemas } from '@/schemas/api/v3/responses/registry';

// Version-aware registry selection
type ResponseSchemaRegistry =
  | typeof v1ResponseSchemas
  | typeof v2ResponseSchemas
  | typeof v3ResponseSchemas;

const registryByVersion: Record<string, ResponseSchemaRegistry> = {
  v1: v1ResponseSchemas,
  v2: v2ResponseSchemas,
  v3: v3ResponseSchemas,
  internal: v3ResponseSchemas, // Internal uses V3 registry
};

function getResponseRegistry(apiName: string): ResponseSchemaRegistry {
  return registryByVersion[apiName] ?? v3ResponseSchemas;
}

// =============================================================================
// Configuration
// =============================================================================

const SCRIPT_DIR = dirname(new URL(import.meta.url).pathname);
const OUTPUT_DIR = join(process.cwd(), 'generated', 'openapi');
const openapiConfig = JSON.parse(
  readFileSync(join(SCRIPT_DIR, 'openapi.config.json'), 'utf-8')
) as {
  servers: Array<{ url: string; description: string }>;
  specTargets: SpecTarget[];
};
const SPEC_TARGETS = openapiConfig.specTargets;
const DRY_RUN = process.argv.includes('--dry-run');
const VERBOSE = process.argv.includes('--verbose') || process.argv.includes('-v');
const NO_TAGS = process.argv.includes('--no-tags');

const SORT_ARG = (() => {
  const idx = process.argv.indexOf('--sort');
  return idx !== -1 ? (process.argv[idx + 1] ?? '').split(',').filter(Boolean) : [];
})();
const SORT_PATHS = SORT_ARG.includes('path');
const SORT_METHODS = SORT_ARG.includes('method');

const FORCE = process.argv.includes('--force');
const TARGET_ARG = (() => {
  const idx = process.argv.indexOf('--target');
  return idx !== -1 ? (process.argv[idx + 1] ?? '').split(',').filter(Boolean) : [];
})();

// =============================================================================
// API Mount Points
// =============================================================================

/** Maps API directory name to its mount path prefix */
const API_MOUNT_PATHS: Record<string, string> = {
  v1: '/api/v1',
  v2: '/api/v2',
  v3: '/api/v3',
  account: '/api/account',
  colonel: '/api/colonel',
  domains: '/api/domains',
  organizations: '/api/organizations',
  invite: '/api/invite',
};

// =============================================================================
// Schema Mapping (scanner-driven)
// =============================================================================

// Scan Ruby source for SCHEMA constants and build lookup map
const scanResult = await scanSchemas();
const handlerSchemaMap = buildHandlerSchemaMap(scanResult.entries);

/**
 * Registry of request schemas, keyed by bare camelCase names.
 *
 * Keys match either:
 *   1. Explicit `request:` values in Ruby SCHEMAS constants
 *   2. Convention-derived keys from handler class names (PascalCase → camelCase)
 *
 * When a handler has no explicit `request:` declaration in Ruby, the generator
 * falls back to convention-based lookup using the handler's leaf class name.
 */
const REQUEST_SCHEMA_REGISTRY: Record<string, z.ZodType> = {
  // Secrets
  burnSecret: burnSecretRequestSchema,
  concealSecret: concealSecretRequestSchema,
  generateSecret: generateSecretRequestSchema,
  listSecretStatus: listSecretStatusRequestSchema,
  revealSecret: revealSecretRequestSchema,
  updateReceipt: updateReceiptRequestSchema,
  showMultipleReceipts: showMultipleReceiptsRequestSchema,

  // Incoming
  createIncomingSecret: createIncomingSecretRequestSchema,
  validateRecipient: validateRecipientRequestSchema,

  // Feedback
  receiveFeedback: receiveFeedbackRequestSchema,
};

/**
 * Look up the response schema key for a route handler.
 * Tries FQCN first, then leaf name fallback.
 */
function lookupResponseSchemaKey(handler: string): string | undefined {
  // Normalize instance-method syntax (#) to module-method syntax (.)
  // so that V1::Controllers::Index#status matches Index.status in the map
  const normalized = handler.replace('#', '.');
  const entry = handlerSchemaMap.get(normalized);
  if (entry) return getResponseKey(entry);

  // Leaf-name fallback
  const leaf = getHandlerLeaf(normalized);
  const leafEntry = handlerSchemaMap.get(leaf);
  if (leafEntry) return getResponseKey(leafEntry);

  return undefined;
}

/**
 * Extract the response key from a SchemaEntry.
 * Returns undefined for model-only entries (no response to emit).
 */
function getResponseKey(entry: SchemaEntry): string | undefined {
  return entry.schema.response;
}

/**
 * Look up the request payload schema for a route handler.
 *
 * Resolution order:
 *   1. Explicit `request:` key from the Ruby SCHEMAS constant
 *   2. Convention-based: handler leaf name → camelCase → registry lookup
 *
 * The convention fallback covers handlers that have a matching request
 * schema in TypeScript but no explicit `request:` declaration in Ruby.
 */
function lookupRequestSchema(handler: string): z.ZodType | undefined {
  const normalized = handler.replace('#', '.');
  const entry =
    handlerSchemaMap.get(normalized) ?? handlerSchemaMap.get(getHandlerLeaf(normalized));

  // Try explicit request key from SCHEMAS constant first
  if (entry) {
    const requestKey = typeof entry.schema === 'string' ? undefined : entry.schema.request;
    if (requestKey) return REQUEST_SCHEMA_REGISTRY[requestKey];
  }

  // Convention-based fallback: derive key from handler leaf name
  const leaf = getHandlerLeaf(normalized);
  const conventionKey = toOperationId(leaf);
  return REQUEST_SCHEMA_REGISTRY[conventionKey];
}

// =============================================================================
// Convention Helpers
// =============================================================================

/**
 * Extract the leaf class name from a namespaced handler.
 * "V3::Logic::Secrets::ConcealSecret" -> "ConcealSecret"
 * "V1::Controllers::Index#show_secret" -> "show_secret"
 */
function getHandlerLeaf(handler: string): string {
  // Handle class/instance method syntax: Class#method or Class.method
  const methodMatch = handler.match(/[#.](\w+)$/);
  if (methodMatch) {
    return methodMatch[1];
  }

  // Handle namespaced logic class: Ns::Ns::ClassName
  const parts = handler.split('::');
  return parts[parts.length - 1];
}

/**
 * Convert PascalCase to camelCase for operationId.
 * "ConcealSecret" -> "concealSecret"
 * "show_secret" -> "showSecret" (snake_case -> camelCase)
 */
function toOperationId(leaf: string): string {
  // Handle snake_case (V1 style)
  if (leaf.includes('_')) {
    return leaf
      .split('_')
      .map((part, i) =>
        i === 0 ? part.toLowerCase() : part.charAt(0).toUpperCase() + part.slice(1).toLowerCase()
      )
      .join('');
  }
  // Handle PascalCase (V2/V3 style)
  return leaf.charAt(0).toLowerCase() + leaf.slice(1);
}

/**
 * Convert PascalCase/snake_case to a human-readable summary.
 * "ConcealSecret" -> "Conceal Secret"
 * "show_secret" -> "Show Secret"
 */
function toSummary(leaf: string): string {
  // Handle snake_case
  if (leaf.includes('_')) {
    return leaf
      .split('_')
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
      .join(' ');
  }
  // Handle PascalCase — insert space before each capital letter
  return leaf.replace(/([A-Z])/g, ' $1').trim();
}

// =============================================================================
// OpenAPI Document Builder
// =============================================================================

interface OpenAPIDocument {
  openapi: string;
  info: {
    title: string;
    version: string;
    description: string;
  };
  servers: Array<{ url: string; description: string }>;
  paths: Record<string, Record<string, unknown>>;
  components: {
    securitySchemes: Record<string, unknown>;
    schemas: Record<string, unknown>;
  };
  tags: Array<{ name: string; description: string }>;
}

function createDocument(target: SpecTarget): OpenAPIDocument {
  return {
    openapi: '3.1.0',
    info: {
      title: target.title,
      version: new Date().toISOString().slice(0, 10), // spec revision date, not API version
      description: target.description,
    },
    servers: openapiConfig.servers,
    paths: {},
    components: {
      securitySchemes: {
        sessionAuth: {
          type: 'apiKey',
          in: 'cookie',
          name: 'rack.session',
          description: 'Session-based authentication via browser cookies',
        },
        basicAuth: {
          type: 'http',
          scheme: 'basic',
          description: 'HTTP Basic authentication with username (email) and API token',
        },
      },
      schemas: {},
    },
    tags: [],
  };
}

/**
 * Convert a Zod schema to an OpenAPI-compatible JSON Schema.
 *
 * Data flow: Wire → Domain → Documentation
 *   .parse(json)                          validates wire input (number)
 *   .transform(v => new Date(v * 1000))   coerces to domain type (Date)
 *   z.toJSONSchema(schema, io:"input")    documents wire type (number)
 *
 * The `io: "input"` option ensures JSON Schema reflects what the API sends
 * (the wire format), not what .parse() returns (the domain type). Without
 * this, transformed output types like Date serialize as `{}`.
 *
 * Note: V2/V3 refer to Onetime Secret API versions, not Zod versions.
 * This project uses Zod v4 for all schemas.
 */
function zodToJsonSchema(schema: z.ZodType): Record<string, unknown> {
  const jsonSchema = z.toJSONSchema(schema, {
    io: 'input',
    unrepresentable: 'any',
    override: (ctx) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const def = (ctx.zodSchema as any)?._zod?.def;
      if (def?.type === 'date') {
        ctx.jsonSchema.type = 'string';
        ctx.jsonSchema.format = 'date-time';
      }
    },
  });
  // $schema is valid at document root but not in inline schemas.
  // OpenAPI 3.1 inherits the JSON Schema dialect from the openapi field.
  delete jsonSchema.$schema;
  return jsonSchema;
}

/**
 * Build the security requirement for a route based on its auth params.
 */
function buildSecurity(route: OttoRoute): Array<Record<string, string[]>> | undefined {
  const auth = getAuthRequirements(route);

  if (!auth.required) {
    return undefined; // No security requirement — publicly accessible
  }

  const security: Array<Record<string, string[]>> = [];

  for (const scheme of auth.schemes) {
    if (scheme === 'sessionauth') {
      security.push({ sessionAuth: [] });
    } else if (scheme === 'basicauth') {
      security.push({ basicAuth: [] });
    }
    // 'noauth' in a mixed scheme list (e.g., basicauth,noauth) means
    // the endpoint also accepts unauthenticated requests. In OpenAPI 3.1,
    // an empty object {} in the security array means "no auth required".
    else if (scheme === 'noauth') {
      security.push({});
    }
  }

  return security.length > 0 ? security : undefined;
}

/**
 * Build path parameters for a route.
 */
function buildPathParameters(path: string): Array<Record<string, unknown>> {
  return getPathParams(path).map((name) => ({
    name,
    in: 'path',
    required: true,
    schema: { type: 'string' },
    description: `The ${name} parameter`,
  }));
}

/**
 * Build the request body for a route.
 *
 * Uses the route's `content` param to select the media type:
 * - content=form → application/x-www-form-urlencoded (V1 API)
 * - default      → application/json (V2/V3 APIs)
 *
 * When a mapped Zod schema exists, its JSON Schema is inlined.
 * For POST/PUT/PATCH routes with content=form but no schema yet,
 * a stub {type: 'object'} is emitted so the spec still documents
 * that the endpoint accepts a request body.
 */
function buildRequestBody(route: OttoRoute): Record<string, unknown> | undefined {
  const schema = lookupRequestSchema(route.handler);
  const contentType = getContentType(route);
  const isForm = contentType === 'form';
  const mediaType = isForm ? 'application/x-www-form-urlencoded' : 'application/json';

  // If we have a schema, emit it under the correct media type
  if (schema) {
    return {
      required: true,
      content: {
        [mediaType]: {
          schema: zodToJsonSchema(schema),
        },
      },
    };
  }

  // For form-encoded routes without a schema, emit a stub so the
  // spec documents the content type even before schemas are wired up
  if (isForm) {
    return {
      required: true,
      content: {
        [mediaType]: {
          schema: { type: 'object' },
        },
      },
    };
  }

  return undefined;
}

/**
 * Build the responses object for a route.
 */
function buildResponses(handler: string, route: OttoRoute, apiName: string): Record<string, unknown> {
  const responseType = getResponseType(route);
  const responses: Record<string, unknown> = {};

  // Version-aware registry selection
  const responseSchemas = getResponseRegistry(apiName);

  // Determine success response via scanner lookup against responseSchemas
  const schemaKey = lookupResponseSchemaKey(handler);
  const responseKey = schemaKey as keyof typeof responseSchemas | undefined;
  if (responseKey && responseSchemas[responseKey]) {
    const schema = responseSchemas[responseKey];
    responses['200'] = {
      description: 'Successful response',
      content: {
        'application/json': {
          schema: zodToJsonSchema(schema),
        },
      },
    };
  } else if (responseType === 'json') {
    responses['200'] = {
      description: 'Successful response',
      content: {
        'application/json': {
          schema: { type: 'object' },
        },
      },
    };
  } else {
    responses['200'] = {
      description: 'Successful response',
    };
  }

  // Add standard error responses based on auth requirements
  const auth = getAuthRequirements(route);
  const errorCodes: (keyof typeof standardErrorResponses)[] = [500];

  if (route.method !== 'GET' && route.method !== 'OPTIONS') {
    errorCodes.unshift(400);
    errorCodes.push(422);
  }
  if (auth.required) {
    errorCodes.push(401);
    errorCodes.push(403);
  }
  errorCodes.push(404);

  for (const code of errorCodes) {
    responses[String(code)] = standardErrorResponses[code];
  }

  return responses;
}

/**
 * Build a qualified operationId that avoids collisions across routes
 * sharing the same handler class (e.g. guest vs authenticated routes).
 *
 * Incorporates the first path segment when a grouping prefix exists
 * (3+ segments, non-parameter first segment) or the route is deprecated.
 */
function qualifyOperationId(apiName: string, operationId: string, route: OttoRoute): string {
  const isDeprecated = route.params.deprecated === 'true';
  const segments = route.path.split('/').filter(Boolean);
  const firstSegment = segments[0] ?? '';
  const hasGroupingPrefix = segments.length >= 3 && firstSegment && !firstSegment.startsWith(':');

  if ((isDeprecated || hasGroupingPrefix) && firstSegment) {
    return `${apiName}_${firstSegment}_${operationId}`;
  }
  return `${apiName}_${operationId}`;
}

/**
 * Build a single OpenAPI operation from an OttoRoute.
 */
function buildOperation(route: OttoRoute, apiName: string): Record<string, unknown> {
  const leaf = getHandlerLeaf(route.handler);
  const operationId = toOperationId(leaf);
  const isDeprecated = route.params.deprecated === 'true';
  const qualifiedOperationId = qualifyOperationId(apiName, operationId, route);

  const operation: Record<string, unknown> = {
    operationId: qualifiedOperationId,
    summary: toSummary(leaf),
  };

  // Add description from @api tag in Ruby class comment (if available)
  const normalizedHandler = route.handler.replace('#', '.');
  const descEntry =
    handlerSchemaMap.get(normalizedHandler) ??
    handlerSchemaMap.get(getHandlerLeaf(normalizedHandler));
  if (descEntry?.description) {
    operation.description = descEntry.description;
  }

  operation.responses = buildResponses(route.handler, route, apiName);

  if (!NO_TAGS) {
    operation.tags = [apiName];
  }

  // Mark deprecated alias routes
  if (isDeprecated) {
    operation.deprecated = true;
  }

  // Emit custom route params as x-o-route-* extensions.
  // Reserved params (consumed by the generator for structural purposes)
  // are excluded — only domain-specific annotations pass through.
  const RESERVED_PARAMS = new Set(['response', 'auth', 'content', 'csrf', 'deprecated']);
  for (const [key, value] of Object.entries(route.params)) {
    if (RESERVED_PARAMS.has(key)) continue;
    operation[`x-otto-route-${key}`] = value;
  }

  // Add security
  const security = buildSecurity(route);
  if (security) {
    operation.security = security;
  } else {
    // Explicitly mark as no auth required
    operation.security = [];
  }

  // Add path parameters
  const pathParams = buildPathParameters(route.path);
  if (pathParams.length > 0) {
    operation.parameters = pathParams;
  }

  // Add request body for POST/PUT/PATCH
  if (['POST', 'PUT', 'PATCH'].includes(route.method)) {
    const requestBody = buildRequestBody(route);
    if (requestBody) {
      operation.requestBody = requestBody;
    }
  }

  return operation;
}

// =============================================================================
// Processing
// =============================================================================

/**
 * Filter routes to only those belonging to the given API names.
 */
function filterRoutes(
  allRoutes: Record<string, { routes: OttoRoute[] }>,
  apiNames: string[]
): Record<string, { routes: OttoRoute[] }> {
  return Object.fromEntries(
    apiNames.filter((name) => name in allRoutes).map((name) => [name, allRoutes[name]])
  );
}

interface ProcessingResult {
  routeCount: number;
  schemaHits: number;
  tags: Set<string>;
}

/**
 * Disambiguate remaining operationId collisions (e.g. GET and POST
 * on the same path sharing a handler) by appending the HTTP method.
 */
function deduplicateOperationId(
  operation: Record<string, unknown>,
  method: string,
  seen: Set<string>
): void {
  const base = operation.operationId as string;
  let opId = base;
  let suffix = 0;
  while (seen.has(opId)) {
    opId = suffix === 0 ? `${base}_${method}` : `${base}_${method}_${suffix}`;
    suffix++;
  }
  if (opId !== base) operation.operationId = opId;
  seen.add(opId);
}

/** Collect tags from an operation into the document-level tag set. */
function collectTags(operation: Record<string, unknown>, tagSet: Set<string>): void {
  if (!NO_TAGS && operation.tags) {
    for (const tag of operation.tags as string[]) tagSet.add(tag);
  }
}

/**
 * Process all API routes into OpenAPI path entries on the document.
 */
function processAllRoutes(
  doc: OpenAPIDocument,
  allRoutes: Record<string, { routes: OttoRoute[] }>
): ProcessingResult {
  const tagSet = new Set<string>();
  let routeCount = 0;
  let schemaHits = 0;

  const seenOperationIds = new Set<string>();

  for (const [apiName, parsed] of Object.entries(allRoutes)) {
    const mountPath = API_MOUNT_PATHS[apiName] || `/api/${apiName}`;

    if (VERBOSE) {
      console.log(`  ${apiName} (${parsed.routes.length} routes, mount: ${mountPath})`);
    }

    for (const route of parsed.routes) {
      // Skip OPTIONS preflight routes
      if (route.method === 'OPTIONS') continue;

      const openApiPath = mountPath + toOpenAPIPath(route.path);
      const method = route.method.toLowerCase();

      if (!doc.paths[openApiPath]) {
        doc.paths[openApiPath] = {};
      }

      const operation = buildOperation(route, apiName);
      deduplicateOperationId(operation, method, seenOperationIds);
      collectTags(operation, tagSet);

      const hasSchema = !!lookupResponseSchemaKey(route.handler);
      if (hasSchema) schemaHits++;

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (doc.paths[openApiPath] as any)[method] = operation;
      routeCount++;

      if (VERBOSE) {
        console.log(`    ${hasSchema ? ' ' : '?'} ${route.method} ${openApiPath}`);
      }
    }
  }

  return { routeCount, schemaHits, tags: tagSet };
}

/** REST method weight for conventional ordering. */
const METHOD_ORDER: Record<string, number> = {
  get: 0,
  post: 1,
  put: 2,
  patch: 3,
  delete: 4,
  options: 5,
  head: 6,
};

/**
 * Sort paths and/or methods in the document according to --sort flags.
 */
function sortPaths(doc: OpenAPIDocument): void {
  if (!SORT_PATHS && !SORT_METHODS) return;

  const pathKeys = SORT_PATHS ? Object.keys(doc.paths).sort() : Object.keys(doc.paths);

  const sorted: typeof doc.paths = {};
  for (const path of pathKeys) {
    const entry = doc.paths[path];
    if (SORT_METHODS) {
      const methodKeys = Object.keys(entry).sort(
        (a, b) => (METHOD_ORDER[a] ?? 99) - (METHOD_ORDER[b] ?? 99)
      );
      const reordered: Record<string, unknown> = {};
      for (const m of methodKeys) {
        reordered[m] = entry[m];
      }
      sorted[path] = reordered;
    } else {
      sorted[path] = entry;
    }
  }
  doc.paths = sorted;
}

/**
 * Write the OpenAPI document to disk and print a per-target summary.
 * Returns the output path for the combined summary.
 */
function writeAndSummarize(
  doc: OpenAPIDocument,
  result: ProcessingResult,
  target: SpecTarget
): string {
  if (!NO_TAGS) {
    doc.tags = Array.from(result.tags)
      .sort()
      .map((name) => ({
        name,
        description: `${name.charAt(0).toUpperCase() + name.slice(1)} operations`,
      }));
  }

  sortPaths(doc);

  const outputPath = join(OUTPUT_DIR, target.filename);

  if (!DRY_RUN) {
    const dir = dirname(outputPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(outputPath, JSON.stringify(doc, null, 2) + '\n');
  }

  const pct = result.routeCount > 0 ? Math.round((result.schemaHits / result.routeCount) * 100) : 0;
  console.log(
    `\n  ${target.id}: ${result.routeCount} routes, ${result.schemaHits} schemas (${pct}%) → ${target.filename}`
  );

  return outputPath;
}

/**
 * Print schema gap report from scanner results.
 */
function printGapReport(result: ScanResult): void {
  if (result.broken.length === 0 && result.uncoveredHandlers.length === 0) return;

  console.log('\nSchema Gaps');
  console.log('───────────────────────');

  for (const entry of result.broken) {
    const key = entry.schema.model ?? entry.schema.response ?? '?';
    console.log(`  Broken: ${entry.className} → ${key}`);
  }

  console.log(`Uncovered handlers (no SCHEMA): ${result.uncoveredHandlers.length}`);
}

// =============================================================================
// Main
// =============================================================================

function main(): void {
  console.log('Generating OpenAPI 3.1 specs from routes.txt...\n');

  if (DRY_RUN) {
    console.log('  [dry-run mode - no files will be written]\n');
  }

  const allRoutes = parseAllApiRoutes();
  const outputs: string[] = [];
  let totalRoutes = 0;
  let totalSchemaHits = 0;

  for (const target of SPEC_TARGETS) {
    // Skip targets not in --target filter (when specified)
    if (TARGET_ARG.length > 0 && !TARGET_ARG.includes(target.id)) {
      continue;
    }

    // Skip frozen targets unless --force
    if (target.frozen && !FORCE) {
      console.log(`  ${target.id}: skipped (frozen — use --force to regenerate)`);
      continue;
    }

    const doc = createDocument(target);
    const filteredRoutes = filterRoutes(allRoutes, target.apiNames);
    const result = processAllRoutes(doc, filteredRoutes);
    const outputPath = writeAndSummarize(doc, result, target);

    outputs.push(outputPath);
    totalRoutes += result.routeCount;
    totalSchemaHits += result.schemaHits;
  }

  // Combined summary
  const pct = totalRoutes > 0 ? Math.round((totalSchemaHits / totalRoutes) * 100) : 0;
  console.log('\nSummary');
  console.log('───────────────────────');
  console.log(`Specs generated:  ${outputs.length}`);
  console.log(`Total routes:     ${totalRoutes}`);
  console.log(`Schema coverage:  ${totalSchemaHits}/${totalRoutes} (${pct}%)`);
  console.log(`Sort:             ${SORT_PATHS || SORT_METHODS ? SORT_ARG.join(',') : 'none'}`);
  for (const path of outputs) {
    console.log(`  → ${path}`);
  }
  console.log(DRY_RUN ? '\nDry run complete. No files written.' : '\nOpenAPI specs generated.');

  // Gap report from scanner
  printGapReport(scanResult);
}

main();
