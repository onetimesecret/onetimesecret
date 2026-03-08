#!/usr/bin/env tsx
// src/scripts/openapi/generate-request-scaffolds.ts
//
// Generates versioned request schema scaffold files from routes.txt.
// Each scaffold is pre-populated with known parameter names from the
// Ruby survey, marked with TODO for human review.
//
// Usage:
//   pnpm run openapi:scaffold-requests              # Generate scaffolds
//   pnpm run openapi:scaffold-requests -- --dry-run  # Preview without writing
//   pnpm run openapi:scaffold-requests -- --force     # Overwrite existing files

import { existsSync, mkdirSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { getPathParams, parseAllApiRoutes, type OttoRoute } from './otto-routes-parser';

// =============================================================================
// Configuration
// =============================================================================

const DRY_RUN = process.argv.includes('--dry-run');
const FORCE = process.argv.includes('--force');
const SCHEMA_BASE = join(process.cwd(), 'src', 'schemas', 'api');

// =============================================================================
// Known Request Parameters (from Ruby source survey)
//
// Each entry maps a handler leaf name to its known request params.
// This is the human-curated knowledge that seeds the scaffolds.
// =============================================================================

interface ParamDef {
  name: string;
  type: 'string' | 'number' | 'boolean' | 'array' | 'object';
  required: boolean;
  description: string;
  /** Zod expression override (e.g. "z.number().int().min(1)" ) */
  zodExpr?: string;
}

interface HandlerParams {
  /** Known body/form params for POST/PUT/PATCH/DELETE */
  body?: ParamDef[];
  /** Known query params for GET */
  query?: ParamDef[];
  /** Notes about this handler's param handling */
  notes?: string;
}

/**
 * Survey-derived parameter knowledge, keyed by handler leaf name.
 * Handlers not listed here get empty scaffolds (TODO-only).
 */
const KNOWN_PARAMS: Record<string, HandlerParams> = {
  // ---------------------------------------------------------------------------
  // V1 Controllers (flat form params)
  // ---------------------------------------------------------------------------

  share: {
    body: [
      {
        name: 'secret',
        type: 'string',
        required: true,
        description: 'The secret content to share',
      },
      {
        name: 'ttl',
        type: 'number',
        required: false,
        description: 'Time-to-live in seconds (default 7 days, min 1800, max 2592000)',
      },
      {
        name: 'passphrase',
        type: 'string',
        required: false,
        description: 'Passphrase to protect the secret',
      },
      {
        name: 'recipient',
        type: 'string',
        required: false,
        description: 'Recipient email address(es)',
      },
      {
        name: 'share_domain',
        type: 'string',
        required: false,
        description: 'Custom domain for the share link',
      },
    ],
    notes: 'Alias for "create". V1 uses flat form params, not nested JSON.',
  },

  generate: {
    body: [
      { name: 'ttl', type: 'number', required: false, description: 'Time-to-live in seconds' },
      {
        name: 'passphrase',
        type: 'string',
        required: false,
        description: 'Passphrase to protect the secret',
      },
      {
        name: 'recipient',
        type: 'string',
        required: false,
        description: 'Recipient email address(es)',
      },
      {
        name: 'share_domain',
        type: 'string',
        required: false,
        description: 'Custom domain for the share link',
      },
    ],
    notes: 'V1 generate — server creates the secret value. Flat form params.',
  },

  create: {
    body: [
      { name: 'secret', type: 'string', required: true, description: 'The secret content' },
      { name: 'ttl', type: 'number', required: false, description: 'Time-to-live in seconds' },
      {
        name: 'passphrase',
        type: 'string',
        required: false,
        description: 'Passphrase to protect the secret',
      },
      {
        name: 'recipient',
        type: 'string',
        required: false,
        description: 'Recipient email address(es)',
      },
      {
        name: 'share_domain',
        type: 'string',
        required: false,
        description: 'Custom domain for the share link',
      },
    ],
    notes: 'Alias for "share". V1 uses flat form params.',
  },

  show_secret: {
    body: [
      {
        name: 'passphrase',
        type: 'string',
        required: false,
        description: 'Passphrase if the secret is protected',
      },
      {
        name: 'continue',
        type: 'string',
        required: false,
        description: 'Set to "true" to proceed with reveal',
      },
    ],
  },

  burn_secret: {
    body: [
      {
        name: 'continue',
        type: 'string',
        required: false,
        description: 'Set to "true" to confirm burn',
      },
    ],
  },

  show_receipt: {
    notes: 'GET requires no body params. POST accepts same as GET (key is in path).',
  },

  show_receipt_recent: {
    notes: 'No request params. Returns recent receipts for authenticated user.',
  },

  status: {
    notes: 'No request params. Returns system status.',
  },

  authcheck: {
    notes: 'No request params. Returns auth status for current session.',
  },

  // ---------------------------------------------------------------------------
  // V2/V3 Logic Classes (JSON body, params nested under "secret" for mutations)
  // ---------------------------------------------------------------------------

  ConcealSecret: {
    body: [
      {
        name: 'secret',
        type: 'string',
        required: true,
        description: 'The secret content to conceal',
      },
      { name: 'ttl', type: 'number', required: false, description: 'Time-to-live in seconds' },
      {
        name: 'passphrase',
        type: 'string',
        required: false,
        description: 'Passphrase to protect the secret',
      },
      {
        name: 'recipient',
        type: 'array',
        required: false,
        description: 'Recipient email address(es)',
        zodExpr: 'z.array(z.email()).optional()',
      },
      {
        name: 'share_domain',
        type: 'string',
        required: false,
        description: 'Custom domain for the share link',
      },
    ],
    notes:
      'V2: params nested under secret={...}. V3: same structure. Existing Zod schemas in payloads/.',
  },

  GenerateSecret: {
    body: [
      { name: 'ttl', type: 'number', required: false, description: 'Time-to-live in seconds' },
      {
        name: 'passphrase',
        type: 'string',
        required: false,
        description: 'Passphrase to protect the secret',
      },
      {
        name: 'recipient',
        type: 'array',
        required: false,
        description: 'Recipient email address(es)',
        zodExpr: 'z.array(z.email()).optional()',
      },
      {
        name: 'share_domain',
        type: 'string',
        required: false,
        description: 'Custom domain for the share link',
      },
    ],
    notes: 'Server generates the secret value. Existing Zod schemas in payloads/.',
  },

  RevealSecret: {
    body: [
      {
        name: 'passphrase',
        type: 'string',
        required: false,
        description: 'Passphrase if the secret is protected',
      },
      {
        name: 'continue',
        type: 'string',
        required: false,
        description: 'Set to "true" to proceed',
      },
    ],
  },

  BurnSecret: {
    body: [
      {
        name: 'continue',
        type: 'string',
        required: false,
        description: 'Set to "true" to confirm burn',
      },
    ],
    notes: 'Identifier is in path param, not body.',
  },

  ShowReceipt: {
    notes: 'GET — no body. Identifier is in path.',
  },

  UpdateReceipt: {
    notes: 'PATCH — body params TBD. Identifier is in path.',
  },

  ListReceipts: {
    notes: 'GET — no body. Returns recent receipts.',
  },

  ShowSecret: {
    notes: 'GET — no body. Identifier is in path.',
  },

  ShowSecretStatus: {
    notes: 'GET — no body. Identifier is in path.',
  },

  ListSecretStatus: {
    body: [
      {
        name: 'identifiers',
        type: 'array',
        required: true,
        description: 'Array of secret identifiers to check',
        zodExpr: 'z.array(z.string())',
      },
    ],
    notes: 'POST with array of identifiers to batch-check status.',
  },

  ShowMultipleReceipts: {
    body: [
      {
        name: 'identifiers',
        type: 'array',
        required: true,
        description: 'Array of receipt identifiers',
        zodExpr: 'z.array(z.string())',
      },
    ],
    notes: 'POST with array of identifiers to batch-fetch receipts.',
  },

  ReceiveFeedback: {
    body: [
      { name: 'message', type: 'string', required: true, description: 'Feedback message content' },
      { name: 'email', type: 'string', required: false, description: 'Contact email (optional)' },
    ],
  },

  CreateIncomingSecret: {
    body: [
      { name: 'secret', type: 'string', required: true, description: 'The secret content' },
      {
        name: 'memo',
        type: 'string',
        required: false,
        description: 'Memo for the recipient (max ~50 chars)',
      },
      {
        name: 'recipient',
        type: 'object',
        required: true,
        description: 'Recipient hash lookup',
        zodExpr: 'z.record(z.string(), z.string())',
      },
    ],
    notes: 'Incoming secret — TTL and passphrase set by config, not request.',
  },

  ValidateRecipient: {
    body: [
      {
        name: 'recipient',
        type: 'string',
        required: true,
        description: 'Recipient hash to validate',
      },
    ],
  },

  GetConfig: {
    notes: 'GET — no body. Returns incoming config.',
  },

  // ---------------------------------------------------------------------------
  // Meta (class methods — no params)
  // ---------------------------------------------------------------------------

  get_supported_locales: { notes: 'GET — no params. Returns locale list.' },
  system_status: { notes: 'GET — no params. Returns status.' },
  system_version: { notes: 'GET — no params. Returns version.' },

  // ---------------------------------------------------------------------------
  // Account API
  // ---------------------------------------------------------------------------

  DestroyAccount: {
    body: [
      {
        name: 'confirmation',
        type: 'string',
        required: true,
        description: 'Confirmation string to delete account',
      },
    ],
  },

  UpdatePassword: {
    body: [
      { name: 'password', type: 'string', required: true, description: 'Current password' },
      {
        name: 'newpassword',
        type: 'string',
        required: true,
        description: 'New password (min 6 chars)',
      },
      {
        name: 'password-confirm',
        type: 'string',
        required: true,
        description: 'New password confirmation (must match)',
      },
    ],
    notes: 'Field name "password-confirm" has a hyphen — needs bracket notation.',
  },

  UpdateDomainContext: {
    body: [
      {
        name: 'domain_extid',
        type: 'string',
        required: false,
        description: 'Domain extid to set as active context (or omit to clear)',
      },
    ],
  },

  UpdateLocale: {
    body: [
      {
        name: 'locale',
        type: 'string',
        required: true,
        description: 'Locale code (e.g. "en", "fr")',
      },
    ],
  },

  UpdateNotificationPreference: {
    body: [
      {
        name: 'field',
        type: 'string',
        required: true,
        description: 'Preference field name (whitelist: notify_on_reveal)',
      },
      {
        name: 'value',
        type: 'string',
        required: true,
        description: 'Boolean string: "true" or "false"',
      },
    ],
  },

  GenerateAPIToken: {
    notes: 'POST — no body params. Generates and returns a new API token.',
  },

  RequestEmailChange: {
    body: [{ name: 'newemail', type: 'string', required: true, description: 'New email address' }],
  },

  ConfirmEmailChange: {
    body: [
      {
        name: 'token',
        type: 'string',
        required: true,
        description: 'Email change confirmation token',
      },
    ],
  },

  ResendEmailChangeConfirmation: {
    notes: 'POST — no body params. Resends confirmation to pending email.',
  },

  GetAccount: { notes: 'GET — no body. Returns account details.' },
  GetEntitlements: { notes: 'GET — no body. Returns entitlement list.' },

  // ---------------------------------------------------------------------------
  // Domains API
  // ---------------------------------------------------------------------------

  AddDomain: {
    body: [
      {
        name: 'domain',
        type: 'string',
        required: true,
        description: 'Domain name to add (validated with PublicSuffix)',
      },
      {
        name: 'org_id',
        type: 'string',
        required: false,
        description: 'Organization ID to associate domain with',
      },
    ],
  },

  RemoveDomain: {
    notes: 'POST — extid in path. No body params.',
  },

  GetDomain: { notes: 'GET — extid in path.' },
  ListDomains: { notes: 'GET — no params.' },
  VerifyDomain: { notes: 'POST — extid in path. Triggers DNS verification.' },
  GetDomainBrand: { notes: 'GET — extid in path.' },

  UpdateDomainBrand: {
    body: [
      {
        name: 'primary_color',
        type: 'string',
        required: false,
        description: 'Hex color for brand',
      },
      { name: 'font_family', type: 'string', required: false, description: 'Font family enum' },
      { name: 'corner_style', type: 'string', required: false, description: 'Corner style enum' },
      {
        name: 'default_ttl',
        type: 'number',
        required: false,
        description: 'Default TTL in seconds (entitlement-gated)',
      },
      {
        name: 'allow_public_homepage',
        type: 'boolean',
        required: false,
        description: 'Allow public homepage (entitlement-gated)',
      },
    ],
    notes: 'Existing Zod schema in v3/requests.ts (updateDomainBrandRequestSchema).',
  },

  GetDnsWidgetToken: { notes: 'GET — no body. Returns DNS widget auth token.' },
  RemoveDomainLogo: { notes: 'DELETE — extid in path.' },
  UpdateDomainLogo: { notes: 'POST — multipart file upload. Extid in path.' },
  GetDomainLogo: { notes: 'GET — extid in path. Returns image.' },
  RemoveDomainIcon: { notes: 'DELETE — extid in path.' },
  UpdateDomainIcon: { notes: 'POST — multipart file upload. Extid in path.' },
  GetDomainIcon: { notes: 'GET — extid in path. Returns image.' },

  // ---------------------------------------------------------------------------
  // Organizations API
  // ---------------------------------------------------------------------------

  ListOrganizations: { notes: 'GET — no params.' },

  CreateOrganization: {
    body: [
      {
        name: 'display_name',
        type: 'string',
        required: true,
        description: 'Organization name (1-100 chars)',
      },
      {
        name: 'description',
        type: 'string',
        required: false,
        description: 'Organization description (0-500 chars)',
      },
      {
        name: 'contact_email',
        type: 'string',
        required: false,
        description: 'Contact email (must be unique)',
      },
    ],
  },

  GetOrganization: { notes: 'GET — extid in path.' },

  UpdateOrganization: {
    body: [
      {
        name: 'display_name',
        type: 'string',
        required: false,
        description: 'Organization name (1-100 chars)',
      },
      {
        name: 'description',
        type: 'string',
        required: false,
        description: 'Organization description (0-500 chars)',
      },
      { name: 'contact_email', type: 'string', required: false, description: 'Contact email' },
    ],
  },

  DeleteOrganization: { notes: 'DELETE — extid in path.' },

  ListInvitations: { notes: 'GET — org extid in path.' },

  CreateInvitation: {
    body: [
      { name: 'email', type: 'string', required: true, description: 'Invitee email address' },
      {
        name: 'role',
        type: 'string',
        required: false,
        description: 'Role: "member" or "admin" (default: "member")',
      },
    ],
  },

  ResendInvitation: { notes: 'POST — org extid + token in path.' },
  RevokeInvitation: { notes: 'DELETE — org extid + token in path.' },

  ListMembers: { notes: 'GET — org extid in path.' },

  UpdateMemberRole: {
    body: [
      {
        name: 'role',
        type: 'string',
        required: true,
        description: 'New role: "member" or "admin"',
      },
    ],
  },

  RemoveMember: { notes: 'DELETE — org extid + member extid in path.' },

  // ---------------------------------------------------------------------------
  // Invite API
  // ---------------------------------------------------------------------------

  ShowInvite: { notes: 'GET — token in path.' },
  AcceptInvite: { notes: 'POST — token in path. No body params (auth validates identity).' },
  DeclineInvite: { notes: 'POST — token in path. No body params.' },

  // ---------------------------------------------------------------------------
  // Colonel (Admin) API
  // ---------------------------------------------------------------------------

  GetColonelInfo: { notes: 'GET — no params.' },
  GetColonelStats: { notes: 'GET — no params.' },
  GetSystemSettings: { notes: 'GET — no params.' },
  GetAvailablePlans: { notes: 'GET — no params.' },

  SetEntitlementTest: {
    body: [
      { name: 'user_id', type: 'string', required: true, description: 'Target user identifier' },
      {
        name: 'entitlement',
        type: 'string',
        required: true,
        description: 'Entitlement name to test',
      },
      {
        name: 'value',
        type: 'boolean',
        required: true,
        description: 'Enable or disable the entitlement',
      },
    ],
  },

  ListSecrets: {
    query: [
      {
        name: 'page',
        type: 'number',
        required: false,
        description: 'Page number (default 1)',
        zodExpr: 'z.number().int().min(1).default(1)',
      },
      {
        name: 'per_page',
        type: 'number',
        required: false,
        description: 'Items per page (default 50, max 100)',
        zodExpr: 'z.number().int().min(1).max(100).default(50)',
      },
    ],
  },

  GetSecretReceipt: { notes: 'GET — secret_id in path.' },
  DeleteSecret: { notes: 'DELETE — secret_id in path.' },

  ListUsers: {
    query: [
      {
        name: 'page',
        type: 'number',
        required: false,
        description: 'Page number (default 1)',
        zodExpr: 'z.number().int().min(1).default(1)',
      },
      {
        name: 'per_page',
        type: 'number',
        required: false,
        description: 'Items per page (default 50, max 100)',
        zodExpr: 'z.number().int().min(1).max(100).default(50)',
      },
    ],
  },

  GetUserDetails: { notes: 'GET — user_id in path.' },

  UpdateUserPlan: {
    body: [
      {
        name: 'planid',
        type: 'string',
        required: true,
        description: 'Plan identifier from billing catalog',
      },
    ],
    notes: 'user_id is in path param.',
  },

  GetDatabaseMetrics: { notes: 'GET — no params.' },
  GetRedisMetrics: { notes: 'GET — no params.' },
  GetQueueMetrics: { notes: 'GET — no params.' },

  ListBannedIPs: {
    query: [
      {
        name: 'page',
        type: 'number',
        required: false,
        description: 'Page number',
        zodExpr: 'z.number().int().min(1).default(1)',
      },
      {
        name: 'per_page',
        type: 'number',
        required: false,
        description: 'Items per page',
        zodExpr: 'z.number().int().min(1).max(100).default(50)',
      },
    ],
  },

  BanIP: {
    body: [
      {
        name: 'ip_address',
        type: 'string',
        required: true,
        description: 'IP address or CIDR range to ban',
      },
      {
        name: 'reason',
        type: 'string',
        required: false,
        description: 'Reason for ban (max 255 chars)',
      },
      {
        name: 'expiration',
        type: 'number',
        required: false,
        description: 'Expiration timestamp (omit for permanent)',
      },
    ],
  },

  UnbanIP: { notes: 'DELETE — IP in path param.' },
  ListCustomDomains: { notes: 'GET — pagination same as ListUsers.' },
  ListOrganizations_colonel: { notes: 'GET — pagination same as ListUsers.' },
  InvestigateOrganization: { notes: 'POST — org_id in path.' },
  ExportUsage: { notes: 'GET — no params. Returns CSV/JSON export.' },
};

// =============================================================================
// API Version Detection
// =============================================================================

/** Map API directory names to schema subdirectory names */
const API_SCHEMA_DIR: Record<string, string> = {
  v1: 'v1',
  v2: 'v2',
  v3: 'v3',
  account: 'account',
  colonel: 'colonel',
  domains: 'domains',
  organizations: 'organizations',
  invite: 'invite',
};

// =============================================================================
// Code Generation
// =============================================================================

function zodTypeExpr(param: ParamDef): string {
  if (param.zodExpr) return param.zodExpr;

  const baseMap: Record<string, string> = {
    string: 'z.string()',
    number: 'z.number().int()',
    boolean: 'z.boolean()',
    array: 'z.array(z.string())',
    object: 'z.record(z.string(), z.unknown())',
  };

  let expr = baseMap[param.type] || 'z.unknown()';
  if (!param.required) {
    expr += '.optional()';
  }
  return expr;
}

/**
 * Extract the handler leaf name.
 * "V3::Logic::Secrets::ConcealSecret" → "ConcealSecret"
 * "V1::Controllers::Index#show_secret" → "show_secret"
 */
function getHandlerLeaf(handler: string): string {
  const methodMatch = handler.match(/[#.](\w+)$/);
  if (methodMatch) return methodMatch[1];
  const parts = handler.split('::');
  return parts[parts.length - 1];
}

/**
 * Convert handler leaf to a schema variable name.
 * "ConcealSecret" → "concealSecretRequestSchema"
 * "show_secret"   → "showSecretRequestSchema"
 */
function toSchemaVarName(leaf: string): string {
  let camel: string;
  if (leaf.includes('_')) {
    // snake_case → camelCase
    camel = leaf
      .split('_')
      .map((part, i) =>
        i === 0 ? part.toLowerCase() : part.charAt(0).toUpperCase() + part.slice(1).toLowerCase()
      )
      .join('');
  } else {
    // PascalCase → camelCase
    camel = leaf.charAt(0).toLowerCase() + leaf.slice(1);
  }
  return `${camel}RequestSchema`;
}

/**
 * Convert handler leaf to a TypeScript type name.
 * "ConcealSecret" → "ConcealSecretRequest"
 * "show_secret"   → "ShowSecretRequest"
 */
function toTypeName(leaf: string): string {
  let pascal: string;
  if (leaf.includes('_')) {
    pascal = leaf
      .split('_')
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
      .join('');
  } else {
    pascal = leaf.charAt(0).toUpperCase() + leaf.slice(1);
  }
  return `${pascal}Request`;
}

/**
 * Convert handler leaf to a kebab-case filename.
 * "ConcealSecret" → "conceal-secret"
 * "show_secret"   → "show-secret"
 * "GenerateAPIToken" → "generate-api-token"
 * "BanIP" → "ban-ip"
 * "ListBannedIPs" → "list-banned-ips"
 */
function toFileName(leaf: string): string {
  if (leaf.includes('_')) {
    return leaf.replace(/_/g, '-').toLowerCase();
  }
  // PascalCase → kebab-case, keeping acronyms together
  // Normalize known pluralized acronyms first, then split
  const normalized = leaf
    .replace(/IPs/g, 'Ips') // IPs → Ips (treat as single word)
    .replace(/APIs/g, 'Apis')
    .replace(/URLs/g, 'Urls')
    .replace(/IDs/g, 'Ids');
  return normalized
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1-$2') // APIToken → API-Token
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2') // conceal-Secret, banned-Ips
    .toLowerCase();
}

interface ScaffoldFile {
  filePath: string;
  content: string;
  apiName: string;
  handler: string;
}

/**
 * Build the file header comment and import line.
 */
function buildHeader(
  schemaDir: string, fileName: string, handler: string,
  method: string, path: string, notes?: string,
): string[] {
  const lines = [
    `// src/schemas/api/${schemaDir}/requests/${fileName}.ts`,
    `//`,
    `// Request schema for ${handler}`,
    `// ${method} ${path}`,
    `//`,
    `// TODO: Review and adjust — this scaffold was auto-generated from`,
    `// the Ruby source parameter survey. Verify against the actual`,
    `// handler implementation before using in the OpenAPI pipeline.`,
  ];
  if (notes) {
    lines.push(`//`, `// ${notes}`);
  }
  lines.push(``, `import { z } from 'zod';`, ``);
  return lines;
}

/**
 * Build z.object({...}) lines from a list of param definitions.
 */
function buildParamObject(varName: string, typeName: string, params: ParamDef[]): string[] {
  const lines: string[] = [`export const ${varName} = z.object({`];
  for (const param of params) {
    const key = param.name.includes('-') ? `'${param.name}'` : param.name;
    lines.push(`  /** ${param.description} */`);
    lines.push(`  ${key}: ${zodTypeExpr(param)},`);
  }
  lines.push(`});`, ``, `export type ${typeName} = z.infer<typeof ${varName}>;`);
  return lines;
}

/**
 * Build schema lines for an endpoint with no known params.
 */
function buildPlaceholder(
  varName: string, typeName: string, handler: string, pathParams: string[],
): string[] {
  const lines: string[] = [];
  if (pathParams.length > 0) {
    lines.push(`// TODO: Add request parameters for this endpoint.`);
    lines.push(`// Path params: ${pathParams.join(', ')}`);
    lines.push(`export const ${varName} = z.object({`);
    lines.push(`  // TODO: fill in from ${handler} raise_concerns / process`);
    lines.push(`});`);
  } else {
    lines.push(`// This endpoint accepts no request parameters.`);
    lines.push(`// Path params (if any) are handled by the OpenAPI generator.`);
    lines.push(`export const ${varName} = z.object({});`);
  }
  lines.push(``, `export type ${typeName} = z.infer<typeof ${varName}>;`);
  return lines;
}

/**
 * Generate the content for a single request schema file.
 */
function generateSchemaFile(route: OttoRoute, apiName: string): ScaffoldFile {
  const leaf = getHandlerLeaf(route.handler);
  const known = KNOWN_PARAMS[leaf];
  const schemaDir = API_SCHEMA_DIR[apiName] || apiName;
  const fileName = toFileName(leaf);
  const varName = toSchemaVarName(leaf);
  const typeName = toTypeName(leaf);

  const header = buildHeader(
    schemaDir, fileName, route.handler, route.method, route.path, known?.notes,
  );

  let body: string[];
  if (known?.body && known.body.length > 0) {
    body = buildParamObject(varName, typeName, known.body);
  } else if (known?.query && known.query.length > 0) {
    body = buildParamObject(varName, typeName, known.query);
  } else {
    body = buildPlaceholder(varName, typeName, route.handler, getPathParams(route.path));
  }

  return {
    filePath: join(SCHEMA_BASE, schemaDir, 'requests', `${fileName}.ts`),
    content: [...header, ...body, ``].join('\n'),
    apiName,
    handler: route.handler,
  };
}

/**
 * Generate index.ts that re-exports all schemas in a directory.
 */
function generateIndexFile(_dirPath: string, fileNames: string[]): string {
  const lines = [
    `// Auto-generated index — re-exports all request schemas in this directory.`,
    `// Regenerate with: pnpm run openapi:scaffold-requests`,
    ``,
  ];
  for (const name of fileNames.sort()) {
    lines.push(`export * from './${name}';`);
  }
  lines.push(``);
  return lines.join('\n');
}

// =============================================================================
// Main
// =============================================================================

/** Track a file in the directory→files map for index generation. */
function trackForIndex(
  dirFiles: Map<string, string[]>, filePath: string, fileName: string,
): void {
  const dir = dirname(filePath);
  if (!dirFiles.has(dir)) dirFiles.set(dir, []);
  dirFiles.get(dir)!.push(fileName);
}

/** Ensure directory exists and write file content. */
function writeScaffold(filePath: string, content: string): void {
  const dir = dirname(filePath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  writeFileSync(filePath, content);
}

/** Deduplicate routes and generate scaffolds for one API. */
function processApi(
  apiName: string, routes: OttoRoute[],
  dirFiles: Map<string, string[]>,
): { generated: number; exists: number; internal: number } {
  const seen = new Set<string>();
  let generated = 0;
  let exists = 0;
  let internal = 0;

  for (const route of routes) {
    if (route.method === 'OPTIONS') continue;
    if (route.params.scope === 'internal') {
      internal++;
      continue;
    }

    const leaf = getHandlerLeaf(route.handler);
    if (seen.has(leaf)) continue;
    seen.add(leaf);

    const scaffold = generateSchemaFile(route, apiName);
    const fileName = toFileName(leaf);

    if (existsSync(scaffold.filePath) && !FORCE) {
      console.log(`  EXISTS  ${scaffold.filePath.replace(process.cwd() + '/', '')}`);
      trackForIndex(dirFiles, scaffold.filePath, fileName);
      exists++;
      continue;
    }

    if (!DRY_RUN) {
      writeScaffold(scaffold.filePath, scaffold.content);
    }
    console.log(`  ${DRY_RUN ? 'WOULD' : 'CREATE'}  ${scaffold.filePath.replace(process.cwd() + '/', '')}`);
    trackForIndex(dirFiles, scaffold.filePath, fileName);
    generated++;
  }

  return { generated, exists, internal };
}

function main(): void {
  console.log('Generating request schema scaffolds from routes.txt...\n');
  if (DRY_RUN) {
    console.log('  [dry-run mode — no files will be written]\n');
  }

  const allRoutes = parseAllApiRoutes();
  const dirFiles = new Map<string, string[]>();
  let totalGenerated = 0;
  let totalExists = 0;
  let totalInternal = 0;

  for (const [apiName, parsed] of Object.entries(allRoutes)) {
    const counts = processApi(apiName, parsed.routes, dirFiles);
    totalGenerated += counts.generated;
    totalExists += counts.exists;
    totalInternal += counts.internal;
  }

  // Generate index.ts for each requests/ directory
  for (const [dir, files] of dirFiles) {
    const indexPath = join(dir, 'index.ts');
    if (!DRY_RUN) {
      writeFileSync(indexPath, generateIndexFile(dir, files));
    }
    console.log(`  ${DRY_RUN ? 'WOULD' : 'CREATE'}  ${indexPath.replace(process.cwd() + '/', '')} (${files.length} exports)`);
  }

  console.log('\nSummary');
  console.log('───────────────────────');
  console.log(`Generated:  ${totalGenerated}`);
  console.log(`Existing:   ${totalExists}`);
  console.log(`Internal:   ${totalInternal} (skipped, scope=internal)`);
  console.log(`Directories: ${dirFiles.size}`);
  console.log(DRY_RUN ? '\nDry run complete. No files written.' : '\nScaffolds generated. Review each file and fill in TODOs.');
}

main();
