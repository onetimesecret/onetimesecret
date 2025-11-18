/**
 * Generate OpenAPI 3.0.3 Specification for V3 API
 *
 * This script generates a complete OpenAPI spec for the V3 API by:
 * 1. Parsing Otto routes files
 * 2. Importing Zod schemas
 * 3. Mapping routes to request/response schemas
 * 4. Generating the complete OpenAPI document
 */

import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { OpenAPIRegistry, OpenApiGeneratorV3 } from '@asteasolutions/zod-to-openapi';
import { z } from '@/schemas/openapi-setup';
import {
  parseApiRoutes,
  getAuthRequirements,
  toOpenAPIPath,
  type OttoRoute
} from './otto-routes-parser';

// Import V3 schemas
import { concealPayloadSchema } from '@/schemas/api/v3/payloads/conceal';
import { generatePayloadSchema } from '@/schemas/api/v3/payloads/generate';
import { responseSchemas } from '@/schemas/api/v3/responses';
import { secretSchema, secretDetailsSchema } from '@/schemas/models/secret';
import { metadataSchema, metadataDetailsSchema } from '@/schemas/models/metadata';

console.log('🔨 Generating OpenAPI Specification for V3 API...\n');

// Parse V3 routes
const v3Routes = parseApiRoutes('v3');
console.log(`📋 Found ${v3Routes.routes.length} routes\n`);

// Initialize OpenAPI registry
const registry = new OpenAPIRegistry();

// Register security schemes
registry.registerComponent('securitySchemes', 'BasicAuth', {
  type: 'http',
  scheme: 'basic',
  description: 'HTTP Basic Authentication using API credentials (username:api_token)'
});

registry.registerComponent('securitySchemes', 'SessionAuth', {
  type: 'apiKey',
  in: 'cookie',
  name: 'sess',
  description: 'Session-based authentication via browser cookie'
});

// Register component schemas
console.log('📦 Registering component schemas...');
registry.register('ConcealPayload', concealPayloadSchema);
registry.register('GeneratePayload', generatePayloadSchema);
registry.register('Secret', secretSchema);
registry.register('SecretDetails', secretDetailsSchema);
registry.register('Metadata', metadataSchema);
registry.register('MetadataDetails', metadataDetailsSchema);
registry.register('SecretResponse', responseSchemas.secret);
registry.register('MetadataResponse', responseSchemas.metadata);
registry.register('ConcealDataResponse', responseSchemas.concealData);

// Error response schema
const errorResponseSchema = z.object({
  message: z.string(),
  code: z.string().optional()
}).openapi('ErrorResponse');
registry.register('ErrorResponse', errorResponseSchema);

console.log('✅ Schemas registered\n');

// Map routes to OpenAPI paths
console.log('🗺️  Mapping routes to OpenAPI paths...');

/**
 * Helper to convert auth schemes to OpenAPI security array
 */
function getSecurityArray(route: OttoRoute) {
  const auth = getAuthRequirements(route);

  if (!auth.required || auth.schemes.length === 0) {
    // No auth required - return empty object to allow anonymous access
    return [{}];
  }

  // Map Otto auth schemes to OpenAPI security schemes
  const security: Array<Record<string, string[]>> = [];

  for (const scheme of auth.schemes) {
    if (scheme === 'sessionauth') {
      security.push({ SessionAuth: [] });
    } else if (scheme === 'basicauth') {
      security.push({ BasicAuth: [] });
    }
  }

  // If no auth or empty array, allow anonymous
  return security.length > 0 ? security : [{}];
}

/**
 * Get tags for a route based on path
 */
function getRouteTags(route: OttoRoute): string[] {
  const tags = ['v3'];

  // Add specific tags based on path
  if (route.path.includes('/secret')) {
    tags.push('secrets');
  }
  if (route.path.includes('/receipt') || route.path.includes('/private')) {
    tags.push('metadata');
  }
  if (route.path.includes('/status') || route.path.includes('/version')) {
    tags.push('system');
  }
  if (route.path.includes('/generate')) {
    tags.push('generate');
  }
  if (route.path.includes('/feedback')) {
    tags.push('feedback');
  }

  return tags;
}

// Register paths based on routes
for (const route of v3Routes.routes) {
  const openApiPath = toOpenAPIPath(route.path);
  const security = getSecurityArray(route);
  const tags = getRouteTags(route);

  // Build path parameters if any
  const pathParams = route.path.match(/:(\w+)/g);
  const params = pathParams
    ? z.object(
        Object.fromEntries(
          pathParams.map(p => [
            p.slice(1), // Remove :
            z.string().openapi({
              param: {
                name: p.slice(1),
                in: 'path'
              }
            })
          ])
        )
      )
    : undefined;

  // Map routes to request/response schemas
  let requestSchema;
  let responseSchema = responseSchemas.metadata; // Default

  // POST /secret/conceal
  if (route.method === 'POST' && route.path === '/secret/conceal') {
    requestSchema = concealPayloadSchema;
    responseSchema = responseSchemas.concealData;

    registry.registerPath({
      method: 'post',
      path: '/api/v3' + openApiPath,
      summary: 'Conceal a secret',
      description: 'Creates an encrypted secret and returns a one-time link. The link can only be viewed once. TTL is limited by plan: 7 days (anonymous), 14 days (basic), 30 days (premium).',
      tags,
      security,
      request: {
        body: {
          content: {
            'application/json': {
              schema: requestSchema
            }
          }
        }
      },
      responses: {
        200: {
          description: 'Secret concealed successfully',
          content: {
            'application/json': {
              schema: responseSchema
            }
          }
        },
        400: {
          description: 'Invalid request - check TTL limits and required fields'
        },
        401: {
          description: 'Unauthorized - invalid or missing credentials'
        },
        429: {
          description: 'Too many requests - rate limit exceeded'
        }
      }
    });
  }
  // POST /secret/generate
  else if (route.method === 'POST' && route.path === '/secret/generate') {
    requestSchema = generatePayloadSchema;
    responseSchema = responseSchemas.concealData;

    registry.registerPath({
      method: 'post',
      path: '/api/v3' + openApiPath,
      summary: 'Generate a secret',
      description: 'Generates a random password and returns a one-time link. The link can only be viewed once.',
      tags,
      security,
      request: {
        body: {
          content: {
            'application/json': {
              schema: requestSchema
            }
          }
        }
      },
      responses: {
        200: {
          description: 'Secret generated successfully',
          content: {
            'application/json': {
              schema: responseSchema
            }
          }
        },
        400: {
          description: 'Invalid request parameters'
        },
        429: {
          description: 'Too many requests - rate limit exceeded'
        }
      }
    });
  }
  // GET /receipt/recent - List recent receipts (must check before parameterized route)
  else if (route.method === 'GET' && route.path === '/receipt/recent') {
    registry.registerPath({
      method: 'get',
      path: '/api/v3' + openApiPath,
      summary: 'List recent receipts',
      description: 'Retrieve a list of recently created secret receipts.',
      tags,
      security,
      responses: {
        200: {
          description: 'Recent receipts retrieved successfully',
          content: {
            'application/json': {
              schema: z.array(responseSchemas.metadata)
            }
          }
        },
        401: {
          description: 'Unauthorized - authentication required'
        }
      }
    });
  }
  // GET /private/recent - List recent private secrets (must check before parameterized route)
  else if (route.method === 'GET' && route.path === '/private/recent') {
    registry.registerPath({
      method: 'get',
      path: '/api/v3' + openApiPath,
      summary: 'List recent private secrets',
      description: 'Retrieve a list of recently created private secrets.',
      tags,
      security,
      responses: {
        200: {
          description: 'Recent private secrets retrieved successfully',
          content: {
            'application/json': {
              schema: z.array(responseSchemas.metadata)
            }
          }
        },
        401: {
          description: 'Unauthorized - authentication required'
        }
      }
    });
  }
  // GET /receipt/:identifier or /private/:identifier - Get metadata by ID
  else if (route.method === 'GET' && (route.path.startsWith('/receipt/') || route.path.startsWith('/private/')) && !route.path.includes('/burn')) {
    registry.registerPath({
      method: 'get',
      path: '/api/v3' + openApiPath,
      summary: 'Get secret metadata',
      description: 'Retrieve metadata for a secret without revealing its value. Shows expiration, state, and other receipt information.',
      tags,
      security,
      request: params ? { params } : undefined,
      responses: {
        200: {
          description: 'Metadata retrieved successfully',
          content: {
            'application/json': {
              schema: responseSchemas.metadata
            }
          }
        },
        404: {
          description: 'Metadata not found or expired'
        }
      }
    });
  }
  // POST /receipt/:identifier/burn
  else if (route.method === 'POST' && route.path.includes('/burn')) {
    registry.registerPath({
      method: 'post',
      path: '/api/v3' + openApiPath,
      summary: 'Burn a secret',
      description: 'Permanently destroy a secret before it expires or is viewed. This action cannot be undone.',
      tags,
      security,
      request: params ? { params } : undefined,
      responses: {
        200: {
          description: 'Secret burned successfully'
        },
        404: {
          description: 'Secret not found or already burned'
        }
      }
    });
  }
  // GET /status
  else if (route.method === 'GET' && route.path === '/status') {
    registry.registerPath({
      method: 'get',
      path: '/api/v3' + openApiPath,
      summary: 'System status',
      description: 'Check if the API is operational',
      tags,
      responses: {
        200: {
          description: 'System is operational',
          content: {
            'application/json': {
              schema: z.object({
                status: z.string(),
                version: z.string()
              })
            }
          }
        }
      }
    });
  }
  // Handle other routes generically
  else {
    console.log(`  ⚠️  Skipping unmapped route: ${route.method} ${route.path}`);
  }
}

console.log('✅ Routes mapped\n');

// Generate OpenAPI document
console.log('📝 Generating OpenAPI document...');

const generator = new OpenApiGeneratorV3(registry.definitions);
const document = generator.generateDocument({
  openapi: '3.0.3',
  info: {
    title: 'Onetime Secret API v3',
    version: '3.0.0',
    description: 'RESTful API for Onetime Secret v3. Returns native JSON types (numbers, booleans, null) instead of string-serialized values like v2.',
    contact: {
      name: 'Onetime Secret Support',
      url: 'https://onetimesecret.com',
      email: 'support@onetimesecret.com'
    },
    license: {
      name: 'MIT',
      url: 'https://opensource.org/licenses/MIT'
    }
  },
  servers: [
    {
      url: 'https://onetimesecret.com/api/v3',
      description: 'Production - Global'
    },
    {
      url: 'https://eu.onetimesecret.com/api/v3',
      description: 'Production - Europe'
    },
    {
      url: 'https://us.onetimesecret.com/api/v3',
      description: 'Production - United States'
    },
    {
      url: 'http://localhost:3000/api/v3',
      description: 'Local development'
    }
  ],
  tags: [
    {
      name: 'v3',
      description: 'API version 3 - Native JSON types'
    },
    {
      name: 'secrets',
      description: 'Secret operations (create, reveal, burn)'
    },
    {
      name: 'metadata',
      description: 'Secret metadata and receipts'
    },
    {
      name: 'generate',
      description: 'Generate random secrets/passwords'
    },
    {
      name: 'system',
      description: 'System status and version information'
    },
    {
      name: 'feedback',
      description: 'User feedback submission'
    }
  ],
  externalDocs: {
    description: 'Full API Documentation',
    url: 'https://docs.onetimesecret.com/api/v3'
  }
});

console.log('✅ Document generated\n');

// Write to file
const outputDir = join(process.cwd(), 'docs', 'api');
mkdirSync(outputDir, { recursive: true });

const outputPath = join(outputDir, 'v3-openapi.json');
writeFileSync(outputPath, JSON.stringify(document, null, 2));

console.log(`💾 Wrote OpenAPI spec to: ${outputPath}\n`);

// Summary
console.log('📊 Summary:');
console.log('─────────────────────');
console.log(`OpenAPI Version: ${document.openapi}`);
console.log(`API Version: ${document.info.version}`);
console.log(`Paths: ${Object.keys(document.paths).length}`);
console.log(`Schemas: ${Object.keys(document.components?.schemas || {}).length}`);
console.log(`Security Schemes: ${Object.keys(document.components?.securitySchemes || {}).length}`);
console.log(`Servers: ${document.servers?.length || 0}`);
console.log(`Tags: ${document.tags?.length || 0}`);
console.log('');
console.log('✅ V3 API OpenAPI specification generated successfully!');
