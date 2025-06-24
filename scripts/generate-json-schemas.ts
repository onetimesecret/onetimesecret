#!/usr/bin/env -S pnpm exec tsx
/**
 * Generate JSON Schemas and TypeScript types from Zod configuration schemas
 *
 * Usage:
 *   pnpm exec tsx scripts/generate-json-schemas.ts           # Generate main schema + types
 *   pnpm exec tsx scripts/generate-json-schemas.ts --openapi # Include OpenAPI schemas
 *   pnpm exec tsx scripts/generate-json-schemas.ts --watch   # Watch mode (future)
 *
 * NOTE: The `-S` flag in the hasbang allows `env` to handle multiple arguments.
 */

import { writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { z } from 'zod/v4';
import { mutableSettingsSchema, staticConfigSchema } from '../src/schemas/config/settings.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const OUTPUT_MAIN_SCHEMA = join(__dirname, '../etc/config.schema.yaml');
const OUTPUT_TYPES = join(__dirname, '../src/types/config.ts');
const OUTPUT_SCHEMAS_DIR = join(__dirname, '../public/web/dist/schemas');

// Combined configuration schema
const combinedConfigSchema = z.object({
  static: staticConfigSchema.optional(),
  dynamic: mutableSettingsSchema.optional(),
});

/**
 * Generate individual JSON schema files
 */
function generateIndividualSchemas(): void {
  mkdirSync(OUTPUT_SCHEMAS_DIR, { recursive: true });

  const schemas = [
    {
      schema: mutableSettingsSchema,
      name: 'mutable-settings',
      description: 'Dynamic mutable settings loaded from mutable_settings.defaults.yaml',
    },
    {
      schema: staticConfigSchema,
      name: 'static-config',
      description: 'Static configuration settings loaded from config.yaml',
    },
    {
      schema: combinedConfigSchema,
      name: 'combined-config',
      description: 'Combined configuration schema for both static and dynamic settings',
    },
  ];

  schemas.forEach(({ schema, name, description }) => {
    const jsonSchema = z.toJSONSchema(schema, {
      target: 'draft-2020-12',
      unrepresentable: 'any',
      cycles: 'ref',
      reused: 'inline',
    });

    const schemaWithMeta = {
      $schema: 'https://json-schema.org/draft/2020-12/schema',
      $id: `https://onetimesecret.com/schemas/${name}.json`,
      title: name
        .split('-')
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' '),
      description,
      ...jsonSchema,
    };

    const outputPath = join(OUTPUT_SCHEMAS_DIR, `${name}.json`);
    writeFileSync(outputPath, JSON.stringify(schemaWithMeta, null, 2));
    console.log(`Generated: ${outputPath}`);
  });
}

/**
 * Generate main configuration schema as YAML
 */
function generateMainSchema(): void {
  const jsonSchema = z.toJSONSchema(staticConfigSchema, {
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

  writeFileSync(OUTPUT_MAIN_SCHEMA, JSON.stringify(schemaWithMeta, null, 2));
  console.log(`Generated: ${OUTPUT_MAIN_SCHEMA}`);
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
import { mutableSettingsSchema, staticConfigSchema } from '@/schemas/config/settings';

export type MutableSettings = z.infer<typeof mutableSettingsSchema>;
export type StaticConfig = z.infer<typeof staticConfigSchema>;

export type ApplicationConfig = {
  static?: StaticConfig;
  dynamic?: MutableSettings;
};

export { mutableSettingsSchema, staticConfigSchema };
`;

  writeFileSync(OUTPUT_TYPES, typeDefinitions);
  console.log(`Generated: ${OUTPUT_TYPES}`);
}

/**
 * Generate OpenAPI schemas (optional)
 */
function generateOpenAPISchemas(): void {
  const schemas = [
    { schema: mutableSettingsSchema, name: 'mutable-settings' },
    { schema: staticConfigSchema, name: 'static-config' },
    { schema: combinedConfigSchema, name: 'combined-config' },
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

    const outputPath = join(OUTPUT_SCHEMAS_DIR, `${name}.openapi.json`);
    writeFileSync(outputPath, JSON.stringify(schemaWithMeta, null, 2));
    console.log(`Generated: ${outputPath}`);
  });
}

/**
 * Main execution
 */
function main(): void {
  const includeOpenAPI = process.argv.includes('--openapi');
  const watchMode = process.argv.includes('--watch');

  if (watchMode) {
    console.log('Watch mode not yet implemented');
    return;
  }

  generateMainSchema();
  generateIndividualSchemas();
  generateTypeDefinitions();

  if (includeOpenAPI) {
    generateOpenAPISchemas();
  }

  console.log('Schema generation complete');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export {
  generateMainSchema,
  generateIndividualSchemas,
  generateTypeDefinitions,
  generateOpenAPISchemas,
};
