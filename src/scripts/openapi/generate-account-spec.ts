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

// Import Account schemas
import { apiTokenSchema, checkAuthDetailsSchema } from '@/schemas/api/account/endpoints/account';
import { colonelInfoDetailsSchema, colonelStatsDetailsSchema } from '@/schemas/api/account/endpoints/colonel';
import { customerSchema } from '@/schemas/models/customer';

// Create OpenAPI-compatible account schema (Stripe types can't be auto-converted)
const accountSchemaForOpenAPI = z.object({
  cust: customerSchema,
  apitoken: z.string().optional(),
  stripe_customer: z.record(z.string(), z.unknown()).nullable().openapi({
    description: 'Stripe Customer object - see https://stripe.com/docs/api/customers/object'
  }),
  stripe_subscriptions: z.array(z.record(z.string(), z.unknown())).nullable().openapi({
    description: 'Array of Stripe Subscription objects - see https://stripe.com/docs/api/subscriptions/object'
  })
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

// Process each route
for (const route of accountRoutes.routes) {
  const openApiPath = toOpenAPIPath(route.path);
  const tags = route.path.includes('/colonel') ? ['account', 'colonel'] : ['account'];
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

  // Route-specific mappings
  if (route.method === 'POST' && route.path === '/account/destroy') {
    registry.registerPath({
      method: 'post',
      path: '/api/account' + openApiPath,
      summary: 'Destroy account',
      description: 'Permanently delete the user account and all associated data. This action cannot be undone.',
      tags,
      security,
      responses: {
        200: {
          description: 'Account destroyed successfully'
        },
        401: {
          description: 'Unauthorized - authentication required'
        },
        500: {
          description: 'Server error during account destruction'
        }
      }
    });
  }
  else if (route.method === 'POST' && route.path === '/account/change-password') {
    registry.registerPath({
      method: 'post',
      path: '/api/account' + openApiPath,
      summary: 'Change password',
      description: 'Update the account password. Requires current password verification.',
      tags,
      security,
      request: {
        body: {
          content: {
            'application/json': {
              schema: z.object({
                current_password: z.string(),
                new_password: z.string().min(6),
                confirm_password: z.string()
              })
            }
          }
        }
      },
      responses: {
        200: {
          description: 'Password changed successfully'
        },
        400: {
          description: 'Invalid request - passwords don\'t match or don\'t meet requirements'
        },
        401: {
          description: 'Unauthorized - current password incorrect'
        }
      }
    });
  }
  else if (route.method === 'POST' && route.path === '/account/update-locale') {
    registry.registerPath({
      method: 'post',
      path: '/api/account' + openApiPath,
      summary: 'Update locale preference',
      description: 'Change the user\'s language preference for the interface.',
      tags,
      security,
      request: {
        body: {
          content: {
            'application/json': {
              schema: z.object({
                locale: z.string().regex(/^[a-z]{2}(-[A-Z]{2})?$/).describe('Language code (e.g., en, es, fr)')
              })
            }
          }
        }
      },
      responses: {
        200: {
          description: 'Locale updated successfully'
        },
        400: {
          description: 'Invalid locale code'
        }
      }
    });
  }
  else if (route.method === 'POST' && route.path === '/account/apitoken') {
    registry.registerPath({
      method: 'post',
      path: '/api/account' + openApiPath,
      summary: 'Generate API token',
      description: 'Generate a new API token for programmatic access. Previous token will be invalidated.',
      tags,
      security,
      responses: {
        200: {
          description: 'API token generated successfully',
          content: {
            'application/json': {
              schema: apiTokenSchema
            }
          }
        },
        401: {
          description: 'Unauthorized - authentication required'
        }
      }
    });
  }
  else if (route.method === 'GET' && route.path === '/account') {
    registry.registerPath({
      method: 'get',
      path: '/api/account' + openApiPath,
      summary: 'Get account details',
      description: 'Retrieve complete account information including Stripe subscription data if applicable.',
      tags,
      security,
      responses: {
        200: {
          description: 'Account details retrieved successfully',
          content: {
            'application/json': {
              schema: accountSchemaForOpenAPI
            }
          }
        },
        401: {
          description: 'Unauthorized - authentication required'
        }
      }
    });
  }
  else if (route.method === 'GET' && route.path === '/colonel/info') {
    registry.registerPath({
      method: 'get',
      path: '/api/account' + openApiPath,
      summary: 'Get colonel dashboard info',
      description: 'Retrieve comprehensive dashboard information for administrators. Requires colonel role.',
      tags,
      security,
      responses: {
        200: {
          description: 'Colonel info retrieved successfully',
          content: {
            'application/json': {
              schema: colonelInfoDetailsSchema
            }
          }
        },
        401: {
          description: 'Unauthorized - authentication required'
        },
        403: {
          description: 'Forbidden - colonel role required'
        }
      }
    });
  }
  else if (route.method === 'GET' && route.path === '/colonel/stats') {
    registry.registerPath({
      method: 'get',
      path: '/api/account' + openApiPath,
      summary: 'Get colonel statistics',
      description: 'Retrieve system-wide statistics for administrators. Requires colonel role.',
      tags,
      security,
      responses: {
        200: {
          description: 'Colonel stats retrieved successfully',
          content: {
            'application/json': {
              schema: colonelStatsDetailsSchema
            }
          }
        },
        401: {
          description: 'Unauthorized - authentication required'
        },
        403: {
          description: 'Forbidden - colonel role required'
        }
      }
    });
  }
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
