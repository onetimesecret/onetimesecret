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
import { join } from 'path';
import { z } from 'zod/v4';
import { configSchema as mutableConfigSchema } from '../schemas/config/mutable';
import { configSchema as staticConfigSchema } from '../schemas/config/static';
import { configSchema as runtimeConfigSchema } from '../schemas/config/runtime';

const ONETIME_HOME = process.env.ONETIME_HOME || process.cwd();

const OUTPUT_MAIN_SCHEMA = join(ONETIME_HOME, 'public/web/dist/schemas/runtime.schema.json');
const OUTPUT_SCHEMAS_DIR = join(ONETIME_HOME, 'etc/schemas');

/**
 * Generate individual JSON schema files
 */
function generateIndividualSchemas(): void {
  mkdirSync(OUTPUT_SCHEMAS_DIR, { recursive: true });

  const schemas = [
    {
      schema: staticConfigSchema,
      name: 'config.schema',
      description: 'Static configuration settings loaded from config.yaml',
    },
    {
      schema: mutableConfigSchema,
      name: 'mutable.schema',
      description: 'Dynamic mutable config loaded from mutable.yaml',
    },
    {
      schema: runtimeConfigSchema,
      name: 'runtime.schema',
      description: 'Combined configuration schema for both static and mutable config',
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
    writeFileSync(outputPath, JSON.stringify(schemaWithMeta, null, 2) + '\n');
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
    $id: 'https://onetimesecret.com/schemas/config.schema.json',
    title: 'OneTimeSecret Configuration',
    description: 'Configuration schema for OneTimeSecret application',
    ...jsonSchema,
  };

  mkdirSync(join(OUTPUT_MAIN_SCHEMA, '..'), { recursive: true });
  writeFileSync(OUTPUT_MAIN_SCHEMA, JSON.stringify(schemaWithMeta, null, 2) + '\n');
  console.log(`Generated: ${OUTPUT_MAIN_SCHEMA}`);
}

/**
 * Generate OpenAPI schemas (optional)
 */
function generateOpenAPISchemas(): void {
  const schemas = [
    { schema: staticConfigSchema, name: 'static' },
    { schema: mutableConfigSchema, name: 'mutable' },
    { schema: runtimeConfigSchema, name: 'runtime' },
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
    writeFileSync(outputPath, JSON.stringify(schemaWithMeta, null, 2) + '\n');
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

  if (includeOpenAPI) {
    generateOpenAPISchemas();
  }

  console.log('Schema generation complete');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { generateMainSchema, generateIndividualSchemas, generateOpenAPISchemas };
