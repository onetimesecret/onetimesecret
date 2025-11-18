/**
 * Generate OpenAPI 3.0.3 Specification for Account API
 *
 * This script generates a complete OpenAPI spec for the Account API by:
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
import { findRouteMapping, mergeResponses, type RouteMapping } from './route-config';

// Import Account schemas
import { apiTokenSchema, checkAuthDetailsSchema } from '@/schemas/api/account/endpoints/account';
import { colonelInfoDetailsSchema, colonelStatsDetailsSchema } from '@/schemas/api/account/endpoints/colonel';
import { customerSchema } from '@/schemas/models/customer';
import { stripeCustomerSchema, stripeSubscriptionSchema } from '@/schemas/api/account/stripe-types';

// Create OpenAPI-compatible account schema with proper Stripe types
const accountSchemaForOpenAPI = z.object({
  cust: customerSchema,
  apitoken: z.string().optional(),
  stripe_customer: stripeCustomerSchema.nullable(),
  stripe_subscriptions: z.array(stripeSubscriptionSchema).nullable()
}).openapi('Account');

console.log('🔨 Generating OpenAPI Specification for Account API...\n');

// Parse Account routes
const accountRoutes = parseApiRoutes('account');
console.log(`📋 Found ${accountRoutes.routes.length} routes\n`);

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
registry.register('Account', accountSchemaForOpenAPI);
registry.register('ApiToken', apiTokenSchema);
registry.register('CheckAuthDetails', checkAuthDetailsSchema);
registry.register('ColonelInfo', colonelInfoDetailsSchema);
registry.register('ColonelStats', colonelStatsDetailsSchema);

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
    return [{}];
  }

  const security: Array<Record<string, string[]>> = [];

  for (const scheme of auth.schemes) {
    if (scheme === 'sessionauth') {
      security.push({ SessionAuth: [] });
    } else if (scheme === 'basicauth') {
      security.push({ BasicAuth: [] });
    }
  }

  return security.length > 0 ? security : [{}];
}

// Request schemas for endpoints that accept input
const changePasswordRequestSchema = z.object({
  current_password: z.string(),
  new_password: z.string().min(6),
  confirm_password: z.string()
}).openapi('ChangePasswordRequest');

const updateLocaleRequestSchema = z.object({
  locale: z.string().regex(/^[a-z]{2}(-[A-Z]{2})?$/).describe('Language code (e.g., en, es, fr)')
}).openapi('UpdateLocaleRequest');

/**
 * Route mapping configuration - declarative approach
 * This replaces the manual if/else chain for better maintainability
 */
const routeMappings: RouteMapping[] = [
  {
    matcher: { method: 'POST', path: '/account/destroy' },
    openapi: {
      summary: 'Destroy account',
      description: 'Permanently delete the user account and all associated data. This action cannot be undone.',
      responses: mergeResponses({
        200: { description: 'Account destroyed successfully' }
      }, [401, 500])
    }
  },
  {
    matcher: { method: 'POST', path: '/account/change-password' },
    openapi: {
      summary: 'Change password',
      description: 'Update the account password. Requires current password verification.',
      requestSchema: changePasswordRequestSchema,
      responses: mergeResponses({
        200: { description: 'Password changed successfully' }
      }, [400, 401])
    }
  },
  {
    matcher: { method: 'POST', path: '/account/update-locale' },
    openapi: {
      summary: 'Update locale preference',
      description: 'Change the user\'s language preference for the interface.',
      requestSchema: updateLocaleRequestSchema,
      responses: mergeResponses({
        200: { description: 'Locale updated successfully' }
      }, [400])
    }
  },
  {
    matcher: { method: 'POST', path: '/account/apitoken' },
    openapi: {
      summary: 'Generate API token',
      description: 'Generate a new API token for programmatic access. Previous token will be invalidated.',
      responseSchema: apiTokenSchema,
      responses: mergeResponses({
        200: {
          description: 'API token generated successfully',
          content: {
            'application/json': {
              schema: apiTokenSchema
            }
          }
        }
      }, [401])
    }
  },
  {
    matcher: { method: 'GET', path: '/account' },
    openapi: {
      summary: 'Get account details',
      description: 'Retrieve complete account information including Stripe subscription data if applicable.',
      responseSchema: accountSchemaForOpenAPI,
      responses: mergeResponses({
        200: {
          description: 'Account details retrieved successfully',
          content: {
            'application/json': {
              schema: accountSchemaForOpenAPI
            }
          }
        }
      }, [401])
    }
  },
  {
    matcher: { method: 'GET', path: '/colonel/info' },
    openapi: {
      summary: 'Get colonel dashboard info',
      description: 'Retrieve comprehensive dashboard information for administrators. Requires colonel role.',
      responseSchema: colonelInfoDetailsSchema,
      tags: ['account', 'colonel'],
      responses: mergeResponses({
        200: {
          description: 'Colonel info retrieved successfully',
          content: {
            'application/json': {
              schema: colonelInfoDetailsSchema
            }
          }
        }
      }, [401, 403])
    }
  },
  {
    matcher: { method: 'GET', path: '/colonel/stats' },
    openapi: {
      summary: 'Get colonel statistics',
      description: 'Retrieve system-wide statistics for administrators. Requires colonel role.',
      responseSchema: colonelStatsDetailsSchema,
      tags: ['account', 'colonel'],
      responses: mergeResponses({
        200: {
          description: 'Colonel stats retrieved successfully',
          content: {
            'application/json': {
              schema: colonelStatsDetailsSchema
            }
          }
        }
      }, [401, 403])
    }
  }
];

// Process each route using the declarative configuration
for (const route of accountRoutes.routes) {
  const openApiPath = toOpenAPIPath(route.path);
  const mapping = findRouteMapping(route, routeMappings);

  if (!mapping) {
    console.log(`  ⚠️  No mapping found for: ${route.method} ${route.path}`);
    continue;
  }

  const tags = mapping.openapi.tags || (route.path.includes('/colonel') ? ['account', 'colonel'] : ['account']);
  const security = getSecurityArray(route);

  // Path parameters
  const pathParams = (openApiPath.match(/\{(\w+)\}/g) || []).map(param => param.slice(1, -1));
  const params = pathParams.length > 0
    ? {
        path: z.object(
          pathParams.reduce((acc, param) => ({ ...acc, [param]: z.string() }), {})
        )
      }
    : undefined;

  // Register the path using the configuration
  registry.registerPath({
    method: route.method.toLowerCase() as any,
    path: '/api/account' + openApiPath,
    summary: mapping.openapi.summary,
    description: mapping.openapi.description,
    tags,
    security,
    request: mapping.openapi.requestSchema
      ? {
          body: {
            content: {
              'application/json': {
                schema: mapping.openapi.requestSchema
              }
            }
          },
          ...(params ? { params } : {})
        }
      : params ? { params } : undefined,
    responses: mapping.openapi.responses
  });
}

console.log(`✅ Registered ${accountRoutes.routes.length} paths\n`);

// Generate OpenAPI document
console.log('📝 Generating OpenAPI document...');

const generator = new OpenApiGeneratorV3(registry.definitions);
const document = generator.generateDocument({
  openapi: '3.0.3',
  info: {
    title: 'Onetime Secret Account API',
    version: '1.0.0',
    description: `
Account management API for Onetime Secret.

**Base URL**: \`/api/account\`

This API handles user account operations including:
- Account management (get, update, delete)
- Password changes
- Locale preferences
- API token generation
- Administrator (colonel) dashboard and statistics

**Authentication**: Most endpoints require session or HTTP Basic authentication.
Some endpoints are restricted to users with the colonel (administrator) role.
    `.trim(),
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
      url: 'https://onetimesecret.com',
      description: 'Production server'
    },
    {
      url: 'https://test.onetimesecret.com',
      description: 'Test server'
    },
    {
      url: 'http://localhost:3000',
      description: 'Local development'
    }
  ],
  tags: [
    {
      name: 'account',
      description: 'Account management operations'
    },
    {
      name: 'colonel',
      description: 'Administrator-only operations (requires colonel role)'
    }
  ]
});

// Write to file
const outputDir = join(process.cwd(), 'docs', 'api');
mkdirSync(outputDir, { recursive: true });
const outputPath = join(outputDir, 'account-openapi.json');

writeFileSync(outputPath, JSON.stringify(document, null, 2), 'utf-8');

console.log(`✅ OpenAPI spec written to: ${outputPath}`);
console.log(`\n📊 Summary:`);
console.log(`   - Routes: ${accountRoutes.routes.length}`);
console.log(`   - Schemas: 6 (Account, ApiToken, ColonelInfo, ColonelStats, CheckAuthDetails, ErrorResponse)`);
console.log(`   - Security schemes: 2 (BasicAuth, SessionAuth)`);
console.log(`   - Tags: 2 (account, colonel)`);
console.log(`\n🎉 Done!\n`);
