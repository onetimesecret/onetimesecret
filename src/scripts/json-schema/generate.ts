#!/usr/bin/env tsx
// src/scripts/json-schema/generate.ts

/**
 * JSON Schema Generator
 *
 * Generates JSON Schema files from Zod schemas in the registry.
 * Output is written to generated/schemas/ for use by:
 * - API documentation
 * - Form validation in non-TypeScript contexts
 * - External tool integration
 * - Ruby backend consumption
 *
 * Usage:
 *   pnpm run schemas:generate           # Generate all schemas
 *   pnpm run schemas:generate --dry-run # Show what would be generated
 *
 * Note on transforms: Schemas using z.preprocess() (e.g., transforms.fromString.boolean)
 * will serialize to their underlying type. The preprocessing logic is runtime-only.
 */

import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { z } from 'zod';
import { schemaRegistry, getSchemasByCategory, type SchemaKey } from '@/schemas/registry';

// =============================================================================
// Configuration
// =============================================================================

const OUTPUT_DIR = join(process.cwd(), 'generated', 'schemas');
const DRY_RUN = process.argv.includes('--dry-run');
const VERBOSE = process.argv.includes('--verbose') || process.argv.includes('-v');

// =============================================================================
// Types
// =============================================================================

interface GenerationResult {
  path: string;
  schema: SchemaKey;
  success: boolean;
  error?: string;
  size?: number;
}

interface ManifestEntry {
  schema: string;
  path: string;
  generatedAt: string;
}

// =============================================================================
// Generation Logic
// =============================================================================

function generateSchema(key: SchemaKey, schema: z.ZodType): Record<string, unknown> {
  try {
    const jsonSchema = z.toJSONSchema(schema, {
      // Prevent throwing on unsupported types (Date, transforms)
      unrepresentable: 'any',

      // Map unsupported Zod types to JSON Schema equivalents
      override: (ctx) => {
        // Access internal Zod type definition (runtime structure)
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const def = (ctx.zodSchema as any)?._zod?.def;
        if (def?.type === 'date') {
          // Map z.date() to ISO 8601 date-time string format
          ctx.jsonSchema.type = 'string';
          ctx.jsonSchema.format = 'date-time';
        }
      },
    });

    // Add $id for schema identification
    return {
      $schema: 'https://json-schema.org/draft/2020-12/schema',
      $id: `https://onetimesecret.com/schemas/${key}.schema.json`,
      ...jsonSchema,
    };
  } catch (error) {
    // If toJSONSchema fails, wrap the error with context
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to generate JSON Schema for '${key}': ${message}`);
  }
}

function writeSchemaFile(key: SchemaKey, jsonSchema: Record<string, unknown>): GenerationResult {
  const relativePath = `${key}.schema.json`;
  const outputPath = join(OUTPUT_DIR, relativePath);

  if (DRY_RUN) {
    console.log(`  [dry-run] Would write: ${relativePath}`);
    return { path: relativePath, schema: key, success: true };
  }

  try {
    // Ensure directory exists
    const dir = dirname(outputPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    // Write JSON with 2-space indentation
    const content = JSON.stringify(jsonSchema, null, 2) + '\n';
    writeFileSync(outputPath, content);

    return {
      path: relativePath,
      schema: key,
      success: true,
      size: content.length,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      path: relativePath,
      schema: key,
      success: false,
      error: message,
    };
  }
}

function writeManifest(results: GenerationResult[]): void {
  const manifest = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    title: 'Onetime Secret Schema Manifest',
    description: 'Index of all generated JSON Schema files',
    generatedAt: new Date().toISOString(),
    schemas: results
      .filter((r) => r.success)
      .map(
        (r): ManifestEntry => ({
          schema: r.schema,
          path: r.path,
          generatedAt: new Date().toISOString(),
        })
      ),
  };

  const manifestPath = join(OUTPUT_DIR, 'manifest.json');

  if (DRY_RUN) {
    console.log(`  [dry-run] Would write: manifest.json`);
    return;
  }

  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

// =============================================================================
// Processing
// =============================================================================

function processSchemaKey(key: SchemaKey): GenerationResult {
  const schema = schemaRegistry[key];

  try {
    const jsonSchema = generateSchema(key, schema);
    return writeSchemaFile(key, jsonSchema);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      path: `${key}.schema.json`,
      schema: key,
      success: false,
      error: message,
    };
  }
}

function logResult(result: GenerationResult): void {
  if (result.success) {
    const sizeInfo = result.size ? ` (${result.size} bytes)` : '';
    if (VERBOSE || DRY_RUN) {
      console.log(`  ✓ ${result.schema}${sizeInfo}`);
    }
  } else {
    console.log(`  ✗ ${result.schema}: ${result.error}`);
  }
}

function printSummary(results: GenerationResult[]): void {
  const successful = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;

  console.log('📊 Summary:');
  console.log('─────────────────────');
  console.log(`Total schemas: ${results.length}`);
  console.log(`Successful: ${successful}`);
  if (failed > 0) {
    console.log(`Failed: ${failed}`);
  }
  console.log(`Output: ${OUTPUT_DIR}/`);
  console.log('');

  if (failed > 0) {
    console.log('⚠️  Some schemas failed to generate. Check errors above.');
    process.exit(1);
  }

  if (DRY_RUN) {
    console.log('✅ Dry run complete. No files were written.');
  } else {
    console.log('✅ JSON Schema generation complete.');
  }
}

// =============================================================================
// Main
// =============================================================================

function main(): void {
  console.log('🔨 Generating JSON Schemas from Zod definitions...\n');

  if (DRY_RUN) {
    console.log('  [dry-run mode - no files will be written]\n');
  }

  const categories = getSchemasByCategory();
  const results: GenerationResult[] = [];

  for (const [category, keys] of Object.entries(categories)) {
    if (keys.length === 0) continue;

    console.log(`📦 ${category}/`);

    for (const key of keys) {
      const result = processSchemaKey(key);
      results.push(result);
      logResult(result);
    }

    console.log('');
  }

  writeManifest(results);
  printSummary(results);
}

main();
