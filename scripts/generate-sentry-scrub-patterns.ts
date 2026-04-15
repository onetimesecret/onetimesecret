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
import {
  API_MOUNT_PATHS,
  parseSensitiveSpec,
  pathToRegexPattern,
} from './openapi/sensitive-spec';

// =============================================================================
// Configuration
// =============================================================================

const OUTPUT_DIR = join(process.cwd(), 'src', 'generated');
const OUTPUT_FILE = join(OUTPUT_DIR, 'sentry-scrub-patterns.ts');
const DRY_RUN = process.argv.includes('--dry-run');
const VERBOSE = process.argv.includes('--verbose') || process.argv.includes('-v');

// =============================================================================
// Pattern Generation
// =============================================================================

interface SensitiveRoute {
  apiName: string;
  method: string;
  fullPath: string;
  pathParams: string[];
  spec: true | Set<string>;
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
 * Validate a single sensitive-route annotation.
 *
 * Performs both structural checks that protect the generator from silently
 * emitting dead or incomplete patterns:
 *
 *   1. Missing-param: when `spec` is a Set of named params, every name must
 *      appear as a `:param` token in the path. Drift between routes.txt and
 *      reality would otherwise cause the author's intended scrub to be
 *      silently skipped.
 *   2. Zero-capture: the resulting regex must emit at least one capture group.
 *      A sensitive annotation that produces zero captures is a misconfigured
 *      route — the path has no `:param` to scrub — and would emit a dead
 *      pattern the frontend can never match.
 *
 * Throws on either violation. Exported so unit tests can exercise both
 * branches directly without booting the full generator pipeline.
 */
export function validateSensitiveRoute(
  method: string,
  fullPath: string,
  pathParams: string[],
  spec: true | Set<string>
): void {
  if (spec !== true) {
    const pathParamSet = new Set(pathParams);
    for (const name of spec) {
      if (!pathParamSet.has(name)) {
        throw new Error(
          `Route ${method} ${fullPath} declares sensitive=${Array.from(spec).join(',')} ` +
            `but :${name} is not a path parameter (path params: ${pathParams.join(', ') || '<none>'})`
        );
      }
    }
  }

  const { captureCount } = pathToRegexPattern(fullPath, spec);
  if (captureCount === 0) {
    throw new Error(
      `Route ${method} ${fullPath} is marked sensitive but ` +
        `produced 0 capture groups — the path has no :param to scrub. ` +
        `Remove the sensitive= annotation or add a path parameter.`
    );
  }
}

/**
 * Filter routes to only those marked as sensitive.
 *
 * Validates that named `sensitive=k1,k2` params actually appear in the path
 * and that the resulting regex has at least one capture group. A mismatch
 * throws — it means routes.txt has drifted from reality and the generated
 * patterns would silently skip whatever the author meant to scrub.
 */
function filterSensitiveRoutes(
  allRoutes: Record<string, { routes: OttoRoute[] }>
): SensitiveRoute[] {
  const sensitiveRoutes: SensitiveRoute[] = [];

  for (const [apiName, parsed] of Object.entries(allRoutes)) {
    const mountPath = API_MOUNT_PATHS[apiName] || `/api/${apiName}`;

    for (const route of parsed.routes) {
      const spec = parseSensitiveSpec(route.params.sensitive);
      if (spec === null) continue;

      const fullPath = mountPath + route.path;
      const pathParams = getPathParams(route.path);

      validateSensitiveRoute(route.method, fullPath, pathParams, spec);

      sensitiveRoutes.push({
        apiName,
        method: route.method,
        fullPath,
        pathParams,
        spec,
        route,
      });
    }
  }

  return sensitiveRoutes;
}

/**
 * Deduplicate patterns by their regex string.
 * Multiple routes may produce the same pattern (e.g., GET and POST on same path).
 *
 * The zero-capture check lives in `validateSensitiveRoute`, which runs earlier
 * in `filterSensitiveRoutes`, so by the time we reach here every route is
 * guaranteed to produce at least one capture group.
 */
function deduplicatePatterns(routes: SensitiveRoute[]): Map<string, SensitiveRoute> {
  const seen = new Map<string, SensitiveRoute>();

  for (const route of routes) {
    const { regex } = pathToRegexPattern(route.fullPath, route.spec);
    if (!seen.has(regex)) {
      seen.set(regex, route);
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
    result = result.replace(pattern, (match, ...args) => {
      // args contains [p1, ..., pN, offset, originalString] — slice off last 2
      const captureGroups = args.slice(0, -2);
      let scrubbed = match;
      for (const group of captureGroups) {
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

// Only run the generator when invoked as a script. Guarding this lets unit
// tests import `validateSensitiveRoute` without triggering a full pipeline
// run (which would parse routes.txt and write to disk).
const invokedAsScript =
  typeof process !== 'undefined' &&
  Array.isArray(process.argv) &&
  process.argv[1] !== undefined &&
  /generate-sentry-scrub-patterns(\.[cm]?ts|\.[cm]?js)?$/.test(process.argv[1]);

if (invokedAsScript) {
  main();
}
