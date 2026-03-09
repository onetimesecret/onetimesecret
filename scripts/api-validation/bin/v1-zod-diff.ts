#!/usr/bin/env -S npx tsx
/**
 * v1-zod-diff.ts
 *
 * Clones the OTS repo at both tags and programmatically extracts + compares
 * the Zod schemas. This gives you a machine-readable diff of declared
 * API contracts between versions.
 *
 * Approach: Since v0.23.4 has no Zod schemas, we instead:
 *   1. Clone main branch, extract all Zod schema field definitions
 *   2. Clone v0.23.4, extract Ruby API response hashes (receipt_hsh, secret_hsh patterns)
 *   3. Compare the two
 *
 * Usage:
 *   npx tsx v1-zod-diff.ts [output_file]
 *
 * This script shells out to git + gh. It needs network access.
 */

import { execSync } from 'child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';

const REPO = 'onetimesecret/onetimesecret';
const OUTPUT = process.argv[2] || './diffs/zod-ruby-diff.json';

// ─── Extract Ruby response hashes from v0.23.4 ───────────────────────

interface RubyField {
  key: string;
  source_expression: string;
  line: number;
}

function extractRubyResponseFields(content: string, filename: string): Record<string, RubyField[]> {
  const methods: Record<string, RubyField[]> = {};
  let currentMethod: string | null = null;
  let braceDepth = 0;
  let inHash = false;
  const fields: RubyField[] = [];

  const lines = content.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // Detect method definitions that return hashes
    // Patterns: def receipt_hsh, def secret_hsh, def success_data, def error_data
    const methodMatch = trimmed.match(/def\s+((?:receipt|secret|metadata|success|error|show)_?(?:hsh|hash|data|response)?)\b/);
    if (methodMatch) {
      currentMethod = methodMatch[1];
      methods[currentMethod] = [];
      continue;
    }

    // Inside a method, look for hash key assignments
    if (currentMethod) {
      // End of method
      if (trimmed === 'end' && braceDepth <= 0) {
        currentMethod = null;
        braceDepth = 0;
        continue;
      }

      // Track brace depth for Ruby hashes
      braceDepth += (trimmed.match(/{/g) || []).length;
      braceDepth -= (trimmed.match(/}/g) || []).length;

      // Hash key patterns:
      //   key: value           (symbol key)
      //   'key' => value       (string key)
      //   :key => value        (symbol => value)
      const symbolKey = trimmed.match(/^\s*(\w+):\s*(.+?)(?:,\s*)?$/);
      const stringKey = trimmed.match(/^\s*['"](\w+)['"]\s*=>\s*(.+?)(?:,\s*)?$/);
      const hashrocketKey = trimmed.match(/^\s*:(\w+)\s*=>\s*(.+?)(?:,\s*)?$/);

      const keyMatch = symbolKey || stringKey || hashrocketKey;
      if (keyMatch) {
        methods[currentMethod].push({
          key: keyMatch[1],
          source_expression: keyMatch[2].replace(/,\s*$/, '').trim(),
          line: i + 1,
        });
      }
    }
  }

  return methods;
}

// ─── Extract Zod schema fields from TypeScript ────────────────────────

interface ZodField {
  key: string;
  zodType: string;
  optional: boolean;
  nullable: boolean;
  transform: boolean;
  line: number;
}

function extractZodFields(content: string): Record<string, ZodField[]> {
  const schemas: Record<string, ZodField[]> = {};
  let currentSchema: string | null = null;
  let currentFields: ZodField[] = [];
  let braceDepth = 0;

  const lines = content.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // Detect schema definitions
    // Patterns:
    //   export const fooSchema = z.object({
    //   const fooSchema = createModelSchema({
    //   export const fooSchema = baseSchema.extend({
    const schemaMatch = trimmed.match(
      /(?:export\s+)?const\s+(\w+Schema)\s*=\s*(?:z\.object|createModelSchema|[\w.]+\.extend)\s*\(\s*\{/
    );

    if (schemaMatch) {
      if (currentSchema && currentFields.length > 0) {
        schemas[currentSchema] = currentFields;
      }
      currentSchema = schemaMatch[1];
      currentFields = [];
      braceDepth = 1;
      continue;
    }

    if (currentSchema && braceDepth > 0) {
      braceDepth += (trimmed.match(/{/g) || []).length;
      braceDepth -= (trimmed.match(/}/g) || []).length;

      if (braceDepth <= 0) {
        schemas[currentSchema] = currentFields;
        currentSchema = null;
        currentFields = [];
        continue;
      }

      // Extract field: zodType patterns
      //   fieldName: z.string(),
      //   fieldName: z.number().optional(),
      //   fieldName: transforms.fromString.number,
      const fieldMatch = trimmed.match(/^\s*(\w+):\s*(.+?)(?:,\s*)?$/);
      if (fieldMatch && braceDepth === 1) {
        const [, key, zodExpr] = fieldMatch;

        // Skip spread operators and method calls
        if (key.startsWith('...') || zodExpr.startsWith('...')) continue;

        currentFields.push({
          key,
          zodType: zodExpr.replace(/,\s*$/, ''),
          optional: /\.optional\(\)/.test(zodExpr) || /\.nullish\(\)/.test(zodExpr),
          nullable: /\.nullable\(\)/.test(zodExpr) || /\.nullish\(\)/.test(zodExpr),
          transform: /transform/.test(zodExpr) || /transforms\./.test(zodExpr) || /preprocess/.test(zodExpr),
          line: i + 1,
        });
      }
    }
  }

  // Don't forget the last schema
  if (currentSchema && currentFields.length > 0) {
    schemas[currentSchema] = currentFields;
  }

  return schemas;
}

// ─── Main ─────────────────────────────────────────────────────────────

async function main() {
  console.log('=== Zod vs Ruby Schema Extraction ===\n');

  mkdirSync('./diffs', { recursive: true });

  // Fetch key files from both refs
  const filesToFetch = {
    'v0.23.4': {
      ruby: [
        'apps/api/v1/controllers/index.rb',
        'apps/api/v1/logic/secrets/base_secret_action.rb',
        'apps/api/v1/logic/secrets/show_secret.rb',
        'apps/api/v1/logic/secrets/generate_secret.rb',
        'apps/api/v1/logic/secrets/show_metadata.rb',
        'apps/api/v1/logic/secrets/burn_secret.rb',
        'apps/api/v1/logic/dashboard.rb',
        'apps/api/v1/models/secret.rb',
        'apps/api/v1/models/metadata.rb',
        'apps/api/v1/controllers/base.rb',
      ],
    },
    'main': {
      ruby: [
        'apps/api/v1/controllers/index.rb',
        'apps/api/v1/logic/secrets/base_secret_action.rb',
        'apps/api/v1/logic/secrets/show_secret.rb',
        'apps/api/v1/logic/secrets/generate_secret.rb',
        'apps/api/v1/logic/secrets/show_receipt.rb',
        'apps/api/v1/logic/secrets/burn_secret.rb',
        'apps/api/v1/controllers/base.rb',
      ],
      zod: [
        'src/schemas/models/secret.ts',
        'src/schemas/models/receipt.ts',
        'src/schemas/models/customer.ts',
        'src/schemas/models/base.ts',
        'src/schemas/api/v3/base.ts',
        'src/schemas/api/v3/responses.ts',
        'src/schemas/api/v3/requests.ts',
        'src/schemas/api/v2/endpoints/secrets.ts',
        'src/schemas/api/v3/payloads/base.ts',
        'src/schemas/api/v3/payloads/conceal.ts',
        'src/schemas/api/v3/payloads/generate.ts',
        'src/schemas/transforms.ts',
      ],
    },
  };

  function fetchFile(path: string, ref: string): string | null {
    try {
      const result = execSync(
        `gh api repos/${REPO}/contents/${path}?ref=${ref} --jq .content 2>/dev/null | base64 -d`,
        { encoding: 'utf-8', timeout: 15000 }
      );
      return result;
    } catch {
      console.log(`  [SKIP] Could not fetch ${path}@${ref}`);
      return null;
    }
  }

  // ── Extract v0.23.4 Ruby fields ──

  console.log('Fetching v0.23.4 Ruby files...');
  const v023RubyFields: Record<string, Record<string, RubyField[]>> = {};

  for (const path of filesToFetch['v0.23.4'].ruby) {
    const content = fetchFile(path, 'v0.23.4');
    if (content) {
      const fields = extractRubyResponseFields(content, path);
      if (Object.keys(fields).length > 0) {
        v023RubyFields[path] = fields;
        console.log(`  [OK] ${path}: ${Object.keys(fields).length} methods found`);
      }
    }
  }

  // ── Extract main Ruby fields ──

  console.log('\nFetching main branch Ruby files...');
  const mainRubyFields: Record<string, Record<string, RubyField[]>> = {};

  for (const path of filesToFetch['main'].ruby) {
    const content = fetchFile(path, 'main');
    if (content) {
      const fields = extractRubyResponseFields(content, path);
      if (Object.keys(fields).length > 0) {
        mainRubyFields[path] = fields;
        console.log(`  [OK] ${path}: ${Object.keys(fields).length} methods found`);
      }
    }
  }

  // ── Extract main Zod schemas ──

  console.log('\nFetching main branch Zod schemas...');
  const mainZodSchemas: Record<string, Record<string, ZodField[]>> = {};

  for (const path of filesToFetch['main'].zod) {
    const content = fetchFile(path, 'main');
    if (content) {
      const schemas = extractZodFields(content);
      if (Object.keys(schemas).length > 0) {
        mainZodSchemas[path] = schemas;
        const schemaNames = Object.keys(schemas).join(', ');
        console.log(`  [OK] ${path}: ${schemaNames}`);
      }
    }
  }

  // ── Build comparison ──

  console.log('\n--- Comparison ---\n');

  // Flatten all field keys from v0.23.4 Ruby response hashes
  const v023AllFields = new Set<string>();
  for (const [_, methods] of Object.entries(v023RubyFields)) {
    for (const [_, fields] of Object.entries(methods)) {
      for (const field of fields) {
        v023AllFields.add(field.key);
      }
    }
  }

  // Flatten all field keys from main Ruby response hashes
  const mainAllRubyFields = new Set<string>();
  for (const [_, methods] of Object.entries(mainRubyFields)) {
    for (const [_, fields] of Object.entries(methods)) {
      for (const field of fields) {
        mainAllRubyFields.add(field.key);
      }
    }
  }

  // Flatten all field keys from main Zod schemas
  const mainAllZodFields = new Set<string>();
  for (const [_, schemas] of Object.entries(mainZodSchemas)) {
    for (const [_, fields] of Object.entries(schemas)) {
      for (const field of fields) {
        mainAllZodFields.add(field.key);
      }
    }
  }

  // Fields in v0.23.4 Ruby but not in main Ruby
  const removedFromRuby = [...v023AllFields].filter(f => !mainAllRubyFields.has(f));
  // Fields in main Ruby but not in v0.23.4
  const addedToRuby = [...mainAllRubyFields].filter(f => !v023AllFields.has(f));

  // Fields in main Zod but not in main Ruby (schema declares more than implementation sends)
  const zodOnly = [...mainAllZodFields].filter(f => !mainAllRubyFields.has(f));
  // Fields in main Ruby but not in Zod (implementation sends more than schema declares)
  const rubyOnly = [...mainAllRubyFields].filter(f => !mainAllZodFields.has(f));

  console.log('Fields removed from Ruby (v0.23.4 -> main):', removedFromRuby);
  console.log('Fields added to Ruby (v0.23.4 -> main):', addedToRuby);
  console.log('Fields in Zod but not Ruby (main):', zodOnly);
  console.log('Fields in Ruby but not Zod (main):', rubyOnly);

  // ── Write report ──

  const report = {
    generated: new Date().toISOString(),
    v023_ruby: {
      files_analyzed: Object.keys(v023RubyFields),
      all_response_fields: [...v023AllFields].sort(),
      methods_by_file: v023RubyFields,
    },
    main_ruby: {
      files_analyzed: Object.keys(mainRubyFields),
      all_response_fields: [...mainAllRubyFields].sort(),
      methods_by_file: mainRubyFields,
    },
    main_zod: {
      files_analyzed: Object.keys(mainZodSchemas),
      all_schema_fields: [...mainAllZodFields].sort(),
      schemas_by_file: mainZodSchemas,
    },
    comparison: {
      ruby_v023_to_main: {
        removed: removedFromRuby,
        added: addedToRuby,
      },
      main_zod_vs_ruby: {
        zod_only: zodOnly,
        ruby_only: rubyOnly,
      },
    },
  };

  writeFileSync(OUTPUT, JSON.stringify(report, null, 2));
  console.log(`\nReport written to: ${OUTPUT}`);
}

main().catch(console.error);
