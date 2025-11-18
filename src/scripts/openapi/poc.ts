/**
 * Proof of Concept: OpenAPI Generation with @asteasolutions/zod-to-openapi
 *
 * Purpose: Validate that the library works with our existing Zod schemas
 * and can generate complete OpenAPI 3.0.3 documents.
 *
 * Tests:
 * 1. Schema registration with .openapi() metadata
 * 2. Factory function compatibility (createApiResponseSchema)
 * 3. Custom transforms compatibility
 * 4. Complete document generation
 * 5. Path registration with security schemes
 */

import { extendZodWithOpenApi, OpenAPIRegistry, OpenApiGeneratorV3 } from '@asteasolutions/zod-to-openapi';
import { z } from 'zod';

// Extend Zod with OpenAPI support
extendZodWithOpenApi(z);

console.log('🔍 Starting OpenAPI PoC...\n');

// ============================================================================
// Test 1: Basic Schema with OpenAPI Metadata
// ============================================================================
console.log('Test 1: Basic schema with .openapi() metadata');

const testUserSchema = z.object({
  id: z.string().openapi({
    description: 'User unique identifier',
    example: 'usr_abc123def456'
  }),
  email: z.string().email().openapi({
    description: 'User email address',
    example: 'user@example.com'
  }),
  active: z.boolean().openapi({
    description: 'Whether the user account is active',
    example: true
  })
}).openapi('User');

console.log('✅ Basic schema created successfully\n');

// ============================================================================
// Test 2: Factory Functions (like our createApiResponseSchema)
// ============================================================================
console.log('Test 2: Factory function compatibility');

const createTestResponseSchema = <T extends z.ZodTypeAny>(recordSchema: T) =>
  z.object({
    user_id: z.string().optional(),
    record: recordSchema,
    details: z.record(z.string(), z.any()).optional()
  });

const userResponseSchema = createTestResponseSchema(testUserSchema).openapi('UserResponse');

console.log('✅ Factory function works with .openapi()\n');

// ============================================================================
// Test 3: Custom Transforms (like our transforms.fromString.number)
// ============================================================================
console.log('Test 3: Custom transform compatibility');

const transformTestSchema = z.object({
  count: z.string().transform((val) => parseInt(val, 10)).openapi({
    description: 'Count as string that transforms to number',
    example: '42',
    type: 'string'
  })
}).openapi('TransformTest');

console.log('✅ Custom transforms work with .openapi()\n');

// ============================================================================
// Test 4: Complete OpenAPI Document Generation
// ============================================================================
console.log('Test 4: Complete OpenAPI document generation');

const registry = new OpenAPIRegistry();

// Register security schemes
registry.registerComponent('securitySchemes', 'BasicAuth', {
  type: 'http',
  scheme: 'basic',
  description: 'HTTP Basic Authentication with username:password'
});

registry.registerComponent('securitySchemes', 'SessionAuth', {
  type: 'apiKey',
  in: 'cookie',
  name: 'sess',
  description: 'Session-based authentication via cookie'
});

// Register schemas as components
registry.register('User', testUserSchema);
registry.register('UserResponse', userResponseSchema);

// Register a path
registry.registerPath({
  method: 'get',
  path: '/api/v3/user/{id}',
  summary: 'Get user by ID',
  description: 'Retrieve a user account by their unique identifier',
  tags: ['v3', 'users'],
  security: [
    { SessionAuth: [] },
    { BasicAuth: [] }
  ],
  request: {
    params: z.object({
      id: z.string().openapi({
        description: 'User identifier',
        example: 'usr_abc123def456'
      })
    })
  },
  responses: {
    200: {
      description: 'User retrieved successfully',
      content: {
        'application/json': {
          schema: userResponseSchema
        }
      }
    },
    401: {
      description: 'Unauthorized - authentication required',
      content: {
        'application/json': {
          schema: z.object({
            message: z.string(),
            code: z.string()
          }).openapi('ErrorResponse')
        }
      }
    },
    404: {
      description: 'User not found'
    }
  }
});

// Generate the OpenAPI document
const generator = new OpenApiGeneratorV3(registry.definitions);
const document = generator.generateDocument({
  openapi: '3.0.3',
  info: {
    title: 'PoC API',
    version: '1.0.0',
    description: 'Proof of concept for OpenAPI generation'
  },
  servers: [
    {
      url: 'https://onetimesecret.com',
      description: 'Production server'
    },
    {
      url: 'https://dev.onetime.dev',
      description: 'Development server'
    }
  ],
  tags: [
    {
      name: 'v3',
      description: 'API version 3 endpoints'
    },
    {
      name: 'users',
      description: 'User management operations'
    }
  ]
});

console.log('✅ OpenAPI document generated successfully\n');

// ============================================================================
// Test 5: Validate Generated Document
// ============================================================================
console.log('Test 5: Validate generated document structure');

const validations = [
  { name: 'Has openapi version', check: document.openapi === '3.0.3' },
  { name: 'Has info object', check: !!document.info },
  { name: 'Has servers', check: Array.isArray(document.servers) && document.servers.length > 0 },
  { name: 'Has paths', check: !!document.paths && Object.keys(document.paths).length > 0 },
  { name: 'Has components', check: !!document.components },
  { name: 'Has schemas', check: !!document.components?.schemas },
  { name: 'Has security schemes', check: !!document.components?.securitySchemes },
  { name: 'User schema exists', check: !!document.components?.schemas?.['User'] },
  { name: 'Path registered', check: !!document.paths['/api/v3/user/{id}'] }
];

let allPassed = true;
for (const validation of validations) {
  if (validation.check) {
    console.log(`  ✅ ${validation.name}`);
  } else {
    console.log(`  ❌ ${validation.name}`);
    allPassed = false;
  }
}

console.log('');

// ============================================================================
// Output Results
// ============================================================================
if (allPassed) {
  console.log('🎉 All tests passed!\n');
  console.log('Generated OpenAPI Document Summary:');
  console.log('─────────────────────────────────');
  console.log(`OpenAPI Version: ${document.openapi}`);
  console.log(`Title: ${document.info.title}`);
  console.log(`Version: ${document.info.version}`);
  console.log(`Servers: ${document.servers?.length || 0}`);
  console.log(`Paths: ${Object.keys(document.paths).length}`);
  console.log(`Schemas: ${Object.keys(document.components?.schemas || {}).length}`);
  console.log(`Security Schemes: ${Object.keys(document.components?.securitySchemes || {}).length}`);
  console.log('');
  console.log('✅ Library is compatible with Onetime Secret!');
  console.log('✅ Ready to proceed with full implementation');
} else {
  console.log('❌ Some tests failed. Review the output above.');
  process.exit(1);
}
