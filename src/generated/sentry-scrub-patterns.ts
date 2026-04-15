// Auto-generated from routes with sensitive=true metadata
// Do not edit manually - regenerate with: pnpm run generate:sentry-patterns
// Generated: 2026-04-15T21:29:12.650Z

/**
 * Regex patterns for scrubbing sensitive path segments from URLs.
 * Derived from Otto routes marked with sensitive=true.
 *
 * These patterns match API paths that contain sensitive identifiers
 * (secret keys, receipt identifiers, etc.) and capture those identifiers
 * for replacement with [REDACTED].
 */
export const SENSITIVE_PATH_PATTERNS: RegExp[] = [
  // /api/v1/metadata/:key
  /\/api\/v1\/metadata\/([^/\s]+)/gi,
  // /api/v1/metadata/:key/burn
  /\/api\/v1\/metadata\/([^/\s]+)\/burn/gi,
  // /api/v1/private/:key
  /\/api\/v1\/private\/([^/\s]+)/gi,
  // /api/v1/private/:key/burn
  /\/api\/v1\/private\/([^/\s]+)\/burn/gi,
  // /api/v1/receipt/:key
  /\/api\/v1\/receipt\/([^/\s]+)/gi,
  // /api/v1/receipt/:key/burn
  /\/api\/v1\/receipt\/([^/\s]+)\/burn/gi,
  // /api/v1/secret/:key
  /\/api\/v1\/secret\/([^/\s]+)/gi,
  // /api/v2/guest/receipt/:identifier
  /\/api\/v2\/guest\/receipt\/([^/\s]+)/gi,
  // /api/v2/guest/receipt/:identifier/burn
  /\/api\/v2\/guest\/receipt\/([^/\s]+)\/burn/gi,
  // /api/v2/guest/secret/:identifier
  /\/api\/v2\/guest\/secret\/([^/\s]+)/gi,
  // /api/v2/guest/secret/:identifier/reveal
  /\/api\/v2\/guest\/secret\/([^/\s]+)\/reveal/gi,
  // /api/v2/private/:identifier
  /\/api\/v2\/private\/([^/\s]+)/gi,
  // /api/v2/private/:identifier/burn
  /\/api\/v2\/private\/([^/\s]+)\/burn/gi,
  // /api/v2/receipt/:identifier
  /\/api\/v2\/receipt\/([^/\s]+)/gi,
  // /api/v2/receipt/:identifier/burn
  /\/api\/v2\/receipt\/([^/\s]+)\/burn/gi,
  // /api/v2/secret/:identifier
  /\/api\/v2\/secret\/([^/\s]+)/gi,
  // /api/v2/secret/:identifier/reveal
  /\/api\/v2\/secret\/([^/\s]+)\/reveal/gi,
  // /api/v2/secret/:identifier/status
  /\/api\/v2\/secret\/([^/\s]+)\/status/gi,
  // /api/v3/guest/receipt/:identifier
  /\/api\/v3\/guest\/receipt\/([^/\s]+)/gi,
  // /api/v3/guest/receipt/:identifier/burn
  /\/api\/v3\/guest\/receipt\/([^/\s]+)\/burn/gi,
  // /api/v3/guest/secret/:identifier
  /\/api\/v3\/guest\/secret\/([^/\s]+)/gi,
  // /api/v3/guest/secret/:identifier/reveal
  /\/api\/v3\/guest\/secret\/([^/\s]+)\/reveal/gi,
  // /api/v3/receipt/:identifier
  /\/api\/v3\/receipt\/([^/\s]+)/gi,
  // /api/v3/receipt/:identifier/burn
  /\/api\/v3\/receipt\/([^/\s]+)\/burn/gi,
  // /api/v3/secret/:identifier
  /\/api\/v3\/secret\/([^/\s]+)/gi,
  // /api/v3/secret/:identifier/reveal
  /\/api\/v3\/secret\/([^/\s]+)\/reveal/gi,
  // /api/v3/secret/:identifier/status
  /\/api\/v3\/secret\/([^/\s]+)\/status/gi,
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
