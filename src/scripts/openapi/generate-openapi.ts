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
  getResponseType,
  type OttoRoute,
} from './otto-routes-parser';

import { standardErrorResponses } from './route-config';

// Optional: import response schemas for enrichment
import { responseSchemas } from '@/schemas/api/v3/responses';
import { concealPayloadSchema } from '@/schemas/api/v3/payloads/conceal';
import { generatePayloadSchema } from '@/schemas/api/v3/payloads/generate';

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
// Schema Mapping
// =============================================================================

/**
 * Maps handler class names to response schema keys.
 * Only entries with known Zod schemas are listed here.
 */
const RESPONSE_SCHEMA_MAP: Record<string, keyof typeof responseSchemas> = {
  // V3 Secrets
  ConcealSecret: 'concealData',
  GenerateSecret: 'concealData',
  ShowSecret: 'secret',
  RevealSecret: 'secret',
  ShowReceipt: 'receipt',
  UpdateReceipt: 'receipt',
  ListReceipts: 'receiptList',
  BurnSecret: 'receipt',
  ShowSecretStatus: 'secret',
  ListSecretStatus: 'secretList',
  ShowMultipleReceipts: 'receiptList',

  // Account
  GetAccount: 'account',
  GetEntitlements: 'account',
  GenerateAPIToken: 'apiToken',

  // Auth
  CheckAuth: 'checkAuth',

  // Colonel
  GetColonelInfo: 'colonelInfo',
  GetColonelStats: 'colonelStats',
  GetSystemSettings: 'systemSettings',
  ListSecrets: 'colonelSecrets',
  ListUsers: 'colonelUsers',
  GetDatabaseMetrics: 'databaseMetrics',
  GetRedisMetrics: 'redisMetrics',
  GetQueueMetrics: 'queueMetrics',
  ListBannedIPs: 'bannedIPs',
  ListCustomDomains: 'customDomains',
  ListOrganizations: 'colonelOrganizations',
  InvestigateOrganization: 'investigateOrganization',
  ExportUsage: 'usageExport',

  // Domains
  GetDomain: 'customDomain',
  ListDomains: 'customDomainList',
  GetDomainBrand: 'brandSettings',
  UpdateDomainBrand: 'brandSettings',
  GetDomainLogo: 'imageProps',
  UpdateDomainLogo: 'imageProps',
  GetDomainIcon: 'imageProps',
  UpdateDomainIcon: 'imageProps',

  // Feedback
  ReceiveFeedback: 'feedback',
};

/**
 * Maps handler class names to request body schemas.
 */
const REQUEST_SCHEMA_MAP: Record<string, z.ZodType> = {
  ConcealSecret: concealPayloadSchema,
  GenerateSecret: generatePayloadSchema,
};

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
 * Uses the same options as the JSON Schema generator.
 */
function zodToJsonSchema(schema: z.ZodType): Record<string, unknown> {
  return z.toJSONSchema(schema, {
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
 * Build the request body for a route, if a schema is mapped.
 */
function buildRequestBody(leaf: string): Record<string, unknown> | undefined {
  const schema = REQUEST_SCHEMA_MAP[leaf];
  if (!schema) return undefined;

  return {
    required: true,
    content: {
      'application/json': {
        schema: zodToJsonSchema(schema),
      },
    },
  };
}

/**
 * Build the responses object for a route.
 */
function buildResponses(
  leaf: string,
  route: OttoRoute
): Record<string, unknown> {
  const responseType = getResponseType(route);
  const responses: Record<string, unknown> = {};

  // Determine success response
  const schemaKey = RESPONSE_SCHEMA_MAP[leaf];
  if (schemaKey && responseSchemas[schemaKey]) {
    const schema = responseSchemas[schemaKey];
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

  // Make operationId unique by prefixing with apiName when needed
  const qualifiedOperationId = `${apiName}_${operationId}`;

  const operation: Record<string, unknown> = {
    operationId: qualifiedOperationId,
    summary: toSummary(leaf),
    tags: [tag],
    responses: buildResponses(leaf, route),
  };

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
    const requestBody = buildRequestBody(leaf);
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

      const leaf = getHandlerLeaf(route.handler);
      if (RESPONSE_SCHEMA_MAP[leaf]) schemaHits++;

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (doc.paths[openApiPath] as any)[method] = operation;
      routeCount++;

      if (VERBOSE) {
        const hasSchema = RESPONSE_SCHEMA_MAP[leaf] ? '+' : ' ';
        console.log(`    ${hasSchema} ${route.method} ${openApiPath}`);
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
