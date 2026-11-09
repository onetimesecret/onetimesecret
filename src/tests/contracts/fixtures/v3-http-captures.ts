import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export interface HttpCapture {
  name: string;
  method: string;
  path: string;
  request: unknown;
  request_schema: string | null;
  response_schema: string | null;
  status: number;
  headers: Record<string, string>;
  body: Record<string, any>;
}

function load(directory: string): HttpCapture[] {
  return readdirSync(directory)
    .filter((file) => file.endsWith('.json')).sort()
    .map((file) => JSON.parse(readFileSync(`${directory}/${file}`, 'utf8')));
}

const archiveDirectory = fileURLToPath(new URL('./api-v3-http', import.meta.url));

// Fresh mounted-Rack captures can exercise both Zod and generated OpenAPI gates.
// Only use synthetic fixtures with cookies, CSRF and credentials stripped.
const freshDirectory = process.env.API_V3_SCHEMA_CAPTURE_DIR;

/** True when the captures come from a fresh producer run, not the archive. */
export const freshCaptureRun = freshDirectory !== undefined;

export const captures: HttpCapture[] = load(freshDirectory ?? archiveDirectory);

/** The committed captures. On a fresh run they are the manifest the producer must match. */
export const archivedCaptures: HttpCapture[] = freshCaptureRun ? load(archiveDirectory) : captures;

/**
 * Archived evidence the mounted producer (spec/integration/simple/api_v3_schema_capture_spec.rb)
 * no longer emits; kept for history and never expected from a fresh run.
 */
export const archiveOnlyCaptureNames: readonly string[] = ['memo-race-generate'];
