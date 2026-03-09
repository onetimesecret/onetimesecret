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
 */

import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { z } from 'zod';

import {
  parseAllApiRoutes,
  toOpenAPIPath,
  getPathParams,
  getAuthRequirements,
  getContentType,
  getResponseType,
  type OttoRoute,
} from './otto-routes-parser';

import { standardErrorResponses } from './route-config';
import { scanSchemas, buildHandlerSchemaMap, type SchemaEntry, type ScanResult } from './schema-scanner';

import { responseSchemas } from '@/schemas/api/v3/responses';
import { concealSecretRequestSchema, generateSecretRequestSchema } from '@/schemas/api/v3/requests';

// =============================================================================
// Configuration
// =============================================================================

const OUTPUT_DIR = join(process.cwd(), 'generated', 'openapi');
const DRY_RUN = process.argv.includes('--dry-run');
const VERBOSE = process.argv.includes('--verbose') || process.argv.includes('-v');

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
 * Registry of request schemas, keyed by bare camelCase names
 * matching the `request:` values in Ruby SCHEMAS constants.
 */
const REQUEST_SCHEMA_REGISTRY: Record<string, z.ZodType> = {
  'concealSecret': concealSecretRequestSchema,
  'generateSecret': generateSecretRequestSchema,
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
 */
function lookupRequestSchema(handler: string): z.ZodType | undefined {
  const normalized = handler.replace('#', '.');
  const entry = handlerSchemaMap.get(normalized)
    ?? handlerSchemaMap.get(getHandlerLeaf(normalized));
  if (!entry) return undefined;

  const requestKey = typeof entry.schema === 'string' ? undefined : entry.schema.request;
  if (!requestKey) return undefined;

  return REQUEST_SCHEMA_REGISTRY[requestKey];
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
      .map((part, i) => i === 0 ? part.toLowerCase() : part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
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
      .map(part => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
      .join(' ');
  }
  // Handle PascalCase — insert space before each capital letter
  return leaf.replace(/([A-Z])/g, ' $1').trim();
}

/**
 * Derive the tag from the API name and handler namespace.
 */
function deriveTag(apiName: string, handler: string): string {
  // Use the namespace segment before the leaf class as the tag
  const parts = handler.split('::');

  // For logic classes: V3::Logic::Secrets::ConcealSecret -> "Secrets"
  // For controllers:  V1::Controllers::Index#method -> "V1"
  if (parts.length >= 3) {
    // Use second-to-last namespace segment
    const namespace = parts[parts.length - 2];
    // Skip generic namespaces
    if (!['Logic', 'Controllers', 'Index'].includes(namespace)) {
      return namespace.toLowerCase();
    }
  }

  // Fallback to API name
  return apiName;
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

function createDocument(): OpenAPIDocument {
  return {
    openapi: '3.1.0',
    info: {
      title: 'Onetime Secret API',
      version: '0.24.0',
      description: 'Auto-generated from Otto routes.txt and Zod v4 schemas.',
    },
    servers: [
      { url: 'https://onetimesecret.com', description: 'Production' },
      { url: 'http://localhost:3000', description: 'Development' },
    ],
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
  return z.toJSONSchema(schema, {
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
  }

  return security.length > 0 ? security : undefined;
}

/**
 * Build path parameters for a route.
 */
function buildPathParameters(path: string): Array<Record<string, unknown>> {
  return getPathParams(path).map(name => ({
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
  const mediaType = isForm
    ? 'application/x-www-form-urlencoded'
    : 'application/json';

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
function buildResponses(
  handler: string,
  route: OttoRoute
): Record<string, unknown> {
  const responseType = getResponseType(route);
  const responses: Record<string, unknown> = {};

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
  }
  if (auth.required) {
    errorCodes.push(401);
    if (auth.role) {
      errorCodes.push(403);
    }
  }
  errorCodes.push(404);

  for (const code of errorCodes) {
    responses[String(code)] = standardErrorResponses[code];
  }

  return responses;
}

/**
 * Build a single OpenAPI operation from an OttoRoute.
 */
function buildOperation(
  route: OttoRoute,
  apiName: string
): Record<string, unknown> {
  const leaf = getHandlerLeaf(route.handler);
  const operationId = toOperationId(leaf);
  const tag = deriveTag(apiName, route.handler);
  const isDeprecated = route.params.deprecated === 'true';

  // Make operationId unique by prefixing with apiName.
  // For deprecated alias routes, also incorporate the path prefix
  // to avoid collisions with the canonical route's operationId.
  let qualifiedOperationId = `${apiName}_${operationId}`;
  if (isDeprecated) {
    const pathPrefix = route.path.split('/').filter(Boolean)[0] ?? '';
    if (pathPrefix) {
      qualifiedOperationId = `${apiName}_${pathPrefix}_${operationId}`;
    }
  }

  const operation: Record<string, unknown> = {
    operationId: qualifiedOperationId,
    summary: toSummary(leaf),
    tags: [tag],
    responses: buildResponses(route.handler, route),
  };

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

interface ProcessingResult {
  routeCount: number;
  schemaHits: number;
  tags: Set<string>;
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
      const tags = operation.tags as string[];
      for (const tag of tags) {
        tagSet.add(tag);
      }

      const hasSchema = !!lookupResponseSchemaKey(route.handler);
      if (hasSchema) schemaHits++;

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (doc.paths[openApiPath] as any)[method] = operation;
      routeCount++;

      if (VERBOSE) {
        console.log(`    ${hasSchema ? '+' : ' '} ${route.method} ${openApiPath}`);
      }
    }
  }

  return { routeCount, schemaHits, tags: tagSet };
}

/**
 * Write the OpenAPI document to disk and print a summary.
 */
function writeAndSummarize(
  doc: OpenAPIDocument,
  result: ProcessingResult,
  apiCount: number
): void {
  doc.tags = Array.from(result.tags).sort().map(name => ({
    name,
    description: `${name.charAt(0).toUpperCase() + name.slice(1)} operations`,
  }));

  const outputPath = join(OUTPUT_DIR, 'openapi.json');

  if (!DRY_RUN) {
    const dir = dirname(outputPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(outputPath, JSON.stringify(doc, null, 2) + '\n');
  }

  const pct = Math.round(result.schemaHits / result.routeCount * 100);
  console.log('\nSummary');
  console.log('───────────────────────');
  console.log(`APIs:             ${apiCount}`);
  console.log(`Routes:           ${result.routeCount}`);
  console.log(`Schema coverage:  ${result.schemaHits}/${result.routeCount} (${pct}%)`);
  console.log(`Tags:             ${result.tags.size}`);
  console.log(`Output:           ${outputPath}`);
  console.log(DRY_RUN ? '\nDry run complete. No files written.' : '\nOpenAPI spec generated.');

  // Gap report from scanner
  printGapReport(scanResult);
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
  if (VERBOSE) {
    for (const handler of result.uncoveredHandlers) {
      console.log(`  ${handler}`);
    }
  }
}

// =============================================================================
// Main
// =============================================================================

function main(): void {
  console.log('Generating OpenAPI 3.1 spec from routes.txt...\n');

  if (DRY_RUN) {
    console.log('  [dry-run mode - no files will be written]\n');
  }

  const doc = createDocument();
  const allRoutes = parseAllApiRoutes();
  const result = processAllRoutes(doc, allRoutes);
  writeAndSummarize(doc, result, Object.keys(allRoutes).length);
}

main();
