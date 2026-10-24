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

// Fresh mounted-Rack captures can exercise both Zod and generated OpenAPI gates.
// Only use synthetic fixtures with cookies, CSRF and credentials stripped.
const directory = process.env.API_V3_SCHEMA_CAPTURE_DIR ?? fileURLToPath(
  new URL('./api-v3-http', import.meta.url)
);
export const captures: HttpCapture[] = readdirSync(directory)
  .filter((file) => file.endsWith('.json')).sort()
  .map((file) => JSON.parse(readFileSync(`${directory}/${file}`, 'utf8')));
