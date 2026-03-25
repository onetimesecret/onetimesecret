// src/scripts/openapi/otto-routes-parser.ts

/**
 * Otto Routes Parser
 *
 * Parses Otto route files to extract endpoint metadata for OpenAPI generation.
 *
 * Otto route file format:
 * METHOD /path HandlerClass param1=value1 param2=value2
 *
 * Example:
 * POST /secret/conceal V3::Logic::Secrets::ConcealSecret response=json auth=noauth csrf=exempt
 *
 * Supported parameters:
 * - response: json|view|redirect|auto
 * - auth: noauth|sessionauth|basicauth|role:colonel (V2+, enforced by Otto)
 * - openapi_auth: basic|anonymous (V1 only, not enforced by Otto)
 * - content: form|json (request body encoding; default json)
 * - csrf: exempt
 */

import { readFileSync, readdirSync, existsSync } from 'fs';
import { join } from 'path';

export interface OttoRoute {
  method: string;
  path: string;
  handler: string;
  params: Record<string, string>;
  raw: string;
  lineNumber: number;
}

export interface ParsedRoutes {
  routes: OttoRoute[];
  filePath: string;
}

/**
 * Parse a single Otto route line
 */
function parseRouteLine(line: string, lineNumber: number): OttoRoute | null {
  // Skip comments and empty lines
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith('#')) {
    return null;
  }

  // Match: METHOD /path Handler [params...]
  // The handler can be namespaced (V3::Logic::Secrets::ConcealSecret)
  const parts = trimmed.split(/\s+/);

  if (parts.length < 3) {
    // Not enough parts for a valid route
    return null;
  }

  const [method, path, handler, ...paramParts] = parts;

  // Parse parameters (key=value format)
  const params: Record<string, string> = {};
  for (const part of paramParts) {
    if (part.includes('=')) {
      const [key, ...valueParts] = part.split('=');
      params[key] = valueParts.join('='); // Handle values with = in them
    }
  }

  return {
    method: method.toUpperCase(),
    path,
    handler,
    params,
    raw: line,
    lineNumber
  };
}

/**
 * Parse an Otto routes file
 */
export function parseRoutesFile(filePath: string): ParsedRoutes {
  const content = readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  const routes: OttoRoute[] = [];

  for (let i = 0; i < lines.length; i++) {
    const route = parseRouteLine(lines[i], i + 1);
    if (route) {
      routes.push(route);
    }
  }

  return {
    routes,
    filePath
  };
}

/**
 * Parse all Otto routes for a specific API
 */
export function parseApiRoutes(apiName: string): ParsedRoutes {
  const routesPath = join(process.cwd(), 'apps', 'api', apiName, 'routes.txt');
  return parseRoutesFile(routesPath);
}

/**
 * Extract authentication requirements from route parameters
 */
export function getAuthRequirements(route: OttoRoute): {
  required: boolean;
  schemes: string[];
  role?: string;
} {
  // V1 uses openapi_auth= (decoupled from Otto's route-level enforcement)
  // V2+ uses auth= (registered with Otto's RouteAuthWrapper)
  // Precedence: auth > openapi_auth. V2+ routes define auth= which Otto
  // enforces at the middleware level. V1 routes define openapi_auth= which
  // is metadata-only — Otto ignores it, but this parser reads it for schema
  // generation. If both are present, auth= wins since it reflects the
  // actually-enforced auth requirement.
  const auth = route.params.auth || route.params.openapi_auth || '';

  if (auth === 'noauth' || auth === '') {
    return { required: false, schemes: [] };
  }

  // Parse comma-separated auth schemes: auth=sessionauth,basicauth
  const schemes = auth.split(',').map(s => s.trim());

  // Normalize V1-era auth tokens to V2+ canonical names.
  // V1 routes use openapi_auth=basic,anonymous; V2+ use auth=basicauth,noauth.
  const schemeMap: Record<string, string> = {
    'basic': 'basicauth',
    'anonymous': 'noauth',
  };

  // Check for role requirement in auth param: auth=role:colonel
  // or as separate param: role=colonel
  const roleScheme = schemes.find(s => s.startsWith('role:'));
  const role = roleScheme ? roleScheme.split(':')[1] : route.params.role;

  // Filter out role from schemes, normalize V1 tokens
  const authSchemes = schemes
    .filter(s => !s.startsWith('role:'))
    .map(s => schemeMap[s] ?? s);

  // An endpoint with only 'noauth' is fully public
  const realAuthSchemes = authSchemes.filter(s => s !== 'noauth');

  return {
    required: realAuthSchemes.length > 0,
    schemes: authSchemes,
    role
  };
}

/**
 * Check if route is CSRF exempt
 */
export function isCsrfExempt(route: OttoRoute): boolean {
  return route.params.csrf === 'exempt';
}

/**
 * Get response type from route
 */
export function getResponseType(route: OttoRoute): string {
  return route.params.response || 'auto';
}

/**
 * Get request content type from route.
 *
 * Returns the content type for request bodies:
 * - 'form' → application/x-www-form-urlencoded (V1 API)
 * - 'json' → application/json (V2/V3 APIs, also the default)
 *
 * When absent, callers should default to 'json'.
 */
export function getContentType(route: OttoRoute): 'form' | 'json' {
  return route.params.content === 'form' ? 'form' : 'json';
}

/**
 * Extract path parameters from route path
 * Example: /secret/:identifier -> ['identifier']
 */
export function getPathParams(path: string): string[] {
  const params: string[] = [];
  const matches = path.matchAll(/:(\w+)/g);

  for (const match of matches) {
    params.push(match[1]);
  }

  return params;
}

/**
 * Convert Otto path to OpenAPI path format
 * Example: /secret/:identifier -> /secret/{identifier}
 */
export function toOpenAPIPath(path: string): string {
  return path.replace(/:(\w+)/g, '{$1}');
}

/**
 * Group routes by tag based on path structure
 */
export function groupRoutesByTag(routes: OttoRoute[]): Map<string, OttoRoute[]> {
  const groups = new Map<string, OttoRoute[]>();

  for (const route of routes) {
    // Extract first path segment as tag
    const pathParts = route.path.split('/').filter(p => p);
    const tag = pathParts[0] || 'default';

    if (!groups.has(tag)) {
      groups.set(tag, []);
    }
    groups.get(tag)!.push(route);
  }

  return groups;
}

/**
 * Discover available API names by scanning the apps/api directory
 */
export function discoverApiNames(): string[] {
  const apiDir = join(process.cwd(), 'apps', 'api');

  try {
    // Read all directories in apps/api/
    const entries = readdirSync(apiDir, { withFileTypes: true });

    // Filter for directories that contain a 'routes.txt' file
    const apiNames = entries
      .filter(entry => entry.isDirectory())
      .map(entry => entry.name)
      .filter(name => {
        const routesPath = join(apiDir, name, 'routes.txt');
        return existsSync(routesPath);
      });

    return apiNames.sort();
  } catch (error) {
    console.warn('Warning: Could not discover API names, using fallback list:', error);
    // Fallback to known APIs if discovery fails
    return ['account', 'colonel', 'domains', 'incoming', 'invite', 'organizations', 'v1', 'v2', 'v3'];
  }
}

/**
 * Parse all API routes for OpenAPI generation
 * Automatically discovers available APIs by scanning apps/api directory
 */
export function parseAllApiRoutes(): Record<string, ParsedRoutes> {
  const apis = discoverApiNames();
  const results: Record<string, ParsedRoutes> = {};

  console.log(`Discovered ${apis.length} APIs: ${apis.join(', ')}`);

  for (const api of apis) {
    try {
      results[api] = parseApiRoutes(api);
    } catch (error) {
      console.warn(`Warning: Could not parse routes for ${api}:`, error);
    }
  }

  return results;
}
