#!/usr/bin/env tsx
/**
 * Generate configuration schema and TypeScript types from Zod schemas.
 *
 * Usage:
 *    # generates schema + types
 *    $ tsx scripts/generate-json-schemas.ts
 *    # generates OpenAPI schema into directory
 *    $ tsx scripts/generate-json-schemas.ts --openapi
 *
 *   OR
 *
 *    $ pnpm run schema:generate
 */

import { writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { z } from 'zod/v4';

import { systemSettingsSchema, staticConfigSchema } from '../src/schemas/config/settings.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const OUTPUT_SCHEMA = join(__dirname, '../etc/config.schema.yaml');
const OUTPUT_TYPES = join(__dirname, '../src/types/config.ts');
const OUTPUT_OPENAPI_DIR = join(__dirname, '../etc/schemas');

// Combined configuration schema
const configSchema = z.object({
  static: staticConfigSchema.optional(),
  dynamic: systemSettingsSchema.optional(),
});

/**
 * Generate main configuration schema as YAML
 */
function generateConfigSchema(): void {
  const jsonSchema = z.toJSONSchema(configSchema, {
    target: 'draft-2020-12',
    unrepresentable: 'any',
    cycles: 'ref',
    reused: 'inline',
  });

  const schemaWithMeta = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://onetimesecret.com/schemas/config.json',
    title: 'OneTimeSecret Configuration',
    description: 'Configuration schema for OneTimeSecret application',
    ...jsonSchema,
  };

  writeFileSync(OUTPUT_SCHEMA, JSON.stringify(schemaWithMeta, null, 2));
  console.log(`Generated: ${OUTPUT_SCHEMA}`);
}

/**
 * Generate TypeScript type definitions
 */
function generateTypeDefinitions(): void {
  mkdirSync(dirname(OUTPUT_TYPES), { recursive: true });

  const typeDefinitions = `/**
 * Configuration type definitions
 * Auto-generated from Zod schemas
 */

import { z } from 'zod/v4';
import { systemSettingsSchema, staticConfigSchema } from '@/schemas/config/settings';

export type SystemSettings = z.infer<typeof systemSettingsSchema>;
export type StaticConfig = z.infer<typeof staticConfigSchema>;

export type ApplicationConfig = {
  static?: StaticConfig;
  dynamic?: SystemSettings;
};

export { systemSettingsSchema, staticConfigSchema };
`;

  writeFileSync(OUTPUT_TYPES, typeDefinitions);
  console.log(`Generated: ${OUTPUT_TYPES}`);
}

/**
 * Generate OpenAPI schemas (optional)
 */
function generateOpenAPISchemas(): void {
  mkdirSync(OUTPUT_OPENAPI_DIR, { recursive: true });

  const schemas = [
    { schema: systemSettingsSchema, name: 'system-settings' },
    { schema: staticConfigSchema, name: 'static-config' },
    { schema: configSchema, name: 'combined-config' },
  ];

  schemas.forEach(({ schema, name }) => {
    const openAPISchema = z.toJSONSchema(schema, {
      target: 'draft-7',
      unrepresentable: 'any',
      cycles: 'ref',
      reused: 'ref',
    });

    const schemaWithMeta = {
      title: name
        .split('-')
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' '),
      description: `OpenAPI schema for ${name}`,
      ...openAPISchema,
    };

    const outputPath = join(OUTPUT_OPENAPI_DIR, `${name}.openapi.json`);
    writeFileSync(outputPath, JSON.stringify(schemaWithMeta, null, 2));
    console.log(`Generated: ${outputPath}`);
  });
}

/**
 * Main execution
 */
function main(): void {
  const includeOpenAPI = process.argv.includes('--openapi');

  generateConfigSchema();
  generateTypeDefinitions();

  if (includeOpenAPI) {
    generateOpenAPISchemas();
  }

  console.log('Schema generation complete');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { generateConfigSchema, generateTypeDefinitions, generateOpenAPISchemas };
