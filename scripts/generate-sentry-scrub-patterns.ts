#!/usr/bin/env tsx

// scripts/generate-sentry-scrub-patterns.ts

/**
 * Sentry Scrub Patterns Generator
 *
 * Generates TypeScript patterns for scrubbing sensitive path segments from URLs.
 * Reads Otto routes annotated with sensitive=true and produces regex patterns
 * that the frontend can use to redact identifiers before sending to Sentry.
 *
 * Usage:
 *   pnpm run generate:sentry-patterns              # Generate patterns
 *   pnpm run generate:sentry-patterns -- --dry-run # Preview without writing
 *   pnpm run generate:sentry-patterns -- --verbose # Show each sensitive route
 */

import { existsSync, mkdirSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { parseAllApiRoutes, type OttoRoute } from './openapi/otto-routes-parser';

// =============================================================================
// Configuration
// =============================================================================

const OUTPUT_DIR = join(process.cwd(), 'src', 'generated');
const OUTPUT_FILE = join(OUTPUT_DIR, 'sentry-scrub-patterns.ts');
const DRY_RUN = process.argv.includes('--dry-run');
const VERBOSE = process.argv.includes('--verbose') || process.argv.includes('-v');

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
  incoming: '/api/incoming',
};

// =============================================================================
// Pattern Generation
// =============================================================================

interface SensitiveRoute {
  apiName: string;
  method: string;
  fullPath: string;
  pathParams: string[];
  route: OttoRoute;
}

/**
 * Extract path parameters from a route path.
 * Example: /secret/:identifier -> ['identifier']
 */
function getPathParams(path: string): string[] {
  const params: string[] = [];
  const matches = path.matchAll(/:(\w+)/g);
  for (const match of matches) {
    params.push(match[1]);
  }
  return params;
}

/**
 * Convert a route path to a regex pattern string.
 * Replaces :param with a capture group for alphanumeric identifiers.
 *
 * Example: /secret/:identifier -> \/secret\/([a-zA-Z0-9]+)
 */
function pathToRegexPattern(path: string): string {
  // Escape forward slashes and replace :param with capture group
  return path
    .replace(/\//g, '\\/')
    .replace(/:(\w+)/g, '([a-zA-Z0-9]+)');
}

/**
 * Filter routes to only those marked as sensitive.
 */
function filterSensitiveRoutes(
  allRoutes: Record<string, { routes: OttoRoute[] }>
): SensitiveRoute[] {
  const sensitiveRoutes: SensitiveRoute[] = [];

  for (const [apiName, parsed] of Object.entries(allRoutes)) {
    const mountPath = API_MOUNT_PATHS[apiName] || `/api/${apiName}`;

    for (const route of parsed.routes) {
      // Check if route is marked as sensitive
      if (route.params.sensitive) {
        const fullPath = mountPath + route.path;
        sensitiveRoutes.push({
          apiName,
          method: route.method,
          fullPath,
          pathParams: getPathParams(route.path),
          route,
        });
      }
    }
  }

  return sensitiveRoutes;
}

/**
 * Deduplicate patterns by their regex string.
 * Multiple routes may produce the same pattern (e.g., GET and POST on same path).
 */
function deduplicatePatterns(routes: SensitiveRoute[]): Map<string, SensitiveRoute> {
  const seen = new Map<string, SensitiveRoute>();

  for (const route of routes) {
    const pattern = pathToRegexPattern(route.fullPath);
    if (!seen.has(pattern)) {
      seen.set(pattern, route);
    }
  }

  return seen;
}

/**
 * Generate the TypeScript output file content.
 */
function generateOutput(patterns: Map<string, SensitiveRoute>): string {
  const sortedPatterns = Array.from(patterns.entries()).sort((a, b) =>
    a[1].fullPath.localeCompare(b[1].fullPath)
  );

  const patternLines = sortedPatterns.map(([pattern, route]) => {
    const comment = `  // ${route.fullPath}`;
    const regex = `  /${pattern}/gi,`;
    return `${comment}\n${regex}`;
  });

  return `// Auto-generated from routes with sensitive=true metadata
// Do not edit manually - regenerate with: pnpm run generate:sentry-patterns
// Generated: ${new Date().toISOString()}

/**
 * Regex patterns for scrubbing sensitive path segments from URLs.
 * Derived from Otto routes marked with sensitive=true.
 *
 * These patterns match API paths that contain sensitive identifiers
 * (secret keys, receipt identifiers, etc.) and capture those identifiers
 * for replacement with [REDACTED].
 */
export const SENSITIVE_PATH_PATTERNS: RegExp[] = [
${patternLines.join('\n')}
];

/**
 * Scrub sensitive identifiers from a URL path.
 * Replaces captured groups with [REDACTED].
 *
 * @param url - The URL string to scrub
 * @returns The scrubbed URL with sensitive identifiers replaced
 *
 * @example
 * scrubSensitivePath('/api/v1/secret/abc123') // => '/api/v1/secret/[REDACTED]'
 * scrubSensitivePath('/api/v3/receipt/xyz789/burn') // => '/api/v3/receipt/[REDACTED]/burn'
 */
export function scrubSensitivePath(url: string): string {
  let result = url;
  for (const pattern of SENSITIVE_PATH_PATTERNS) {
    pattern.lastIndex = 0; // Reset global regex state
    result = result.replace(pattern, (match, ...groups) => {
      // Replace each captured group with [REDACTED]
      let scrubbed = match;
      for (const group of groups) {
        if (typeof group === 'string') {
          scrubbed = scrubbed.replace(group, '[REDACTED]');
        }
      }
      return scrubbed;
    });
  }
  return result;
}
`;
}

// =============================================================================
// Main
// =============================================================================

function main(): void {
  console.log('Generating Sentry scrub patterns from routes.txt...\n');

  if (DRY_RUN) {
    console.log('  [dry-run mode - no files will be written]\n');
  }

  // Parse all API routes
  const allRoutes = parseAllApiRoutes();

  // Filter to sensitive routes only
  const sensitiveRoutes = filterSensitiveRoutes(allRoutes);

  if (VERBOSE) {
    console.log('\nSensitive routes found:');
    for (const route of sensitiveRoutes) {
      const params = route.pathParams.length > 0
        ? ` (params: ${route.pathParams.join(', ')})`
        : '';
      console.log(`  ${route.method.padEnd(6)} ${route.fullPath}${params}`);
    }
  }

  // Deduplicate patterns
  const uniquePatterns = deduplicatePatterns(sensitiveRoutes);

  // Generate output
  const output = generateOutput(uniquePatterns);

  if (DRY_RUN) {
    console.log('\n--- Generated output (preview) ---\n');
    console.log(output);
    console.log('--- End preview ---\n');
  } else {
    // Ensure output directory exists
    if (!existsSync(OUTPUT_DIR)) {
      mkdirSync(OUTPUT_DIR, { recursive: true });
      console.log(`Created directory: ${OUTPUT_DIR}`);
    }

    // Write the output file
    writeFileSync(OUTPUT_FILE, output);
    console.log(`\nWrote: ${OUTPUT_FILE}`);
  }

  // Summary
  console.log('\nSummary');
  console.log('-------------------');
  console.log(`Total sensitive routes: ${sensitiveRoutes.length}`);
  console.log(`Unique patterns:        ${uniquePatterns.size}`);
  console.log(DRY_RUN ? '\nDry run complete. No files written.' : '\nPatterns generated.');
}

main();
