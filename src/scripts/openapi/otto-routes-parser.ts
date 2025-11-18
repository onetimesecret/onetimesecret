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
 * - auth: noauth|sessionauth|basicauth|role:colonel
 * - csrf: exempt
 */

import { readFileSync } from 'fs';
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
  const routesPath = join(process.cwd(), 'apps', 'api', apiName, 'routes');
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
  const auth = route.params.auth || '';

  if (auth === 'noauth' || auth === '') {
    return { required: false, schemes: [] };
  }

  // Parse comma-separated auth schemes: auth=sessionauth,basicauth
  const schemes = auth.split(',').map(s => s.trim());

  // Check for role requirement: auth=role:colonel
  const roleScheme = schemes.find(s => s.startsWith('role:'));
  const role = roleScheme ? roleScheme.split(':')[1] : undefined;

  // Filter out role from schemes
  const authSchemes = schemes.filter(s => !s.startsWith('role:'));

  return {
    required: authSchemes.length > 0,
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
 * Parse all API routes for OpenAPI generation
 */
export function parseAllApiRoutes(): Record<string, ParsedRoutes> {
  const apis = ['v2', 'v3', 'account', 'domains', 'organizations', 'teams'];
  const results: Record<string, ParsedRoutes> = {};

  for (const api of apis) {
    try {
      results[api] = parseApiRoutes(api);
    } catch (error) {
      console.warn(`Warning: Could not parse routes for ${api}:`, error);
    }
  }

  return results;
}
