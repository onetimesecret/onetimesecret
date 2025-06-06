#!/usr/bin/env tsx
/**
 * Generate JSON Schemas from Zod configuration schemas
 * Uses Zod v4 native JSON Schema conversion
 */

import { writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { z } from 'zod/v4';
import { systemSettingsSchema, staticConfigSchema } from '../src/schemas/config/settings.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const outputDir = join(__dirname, '../etc/schemas');

// Ensure output directory exists
mkdirSync(outputDir, { recursive: true });

/**
 * Generate JSON Schema with Zod v4 native conversion
 */
function generateJSONSchema(schema: z.ZodTypeAny, name: string, description?: string) {
  console.log(`Generating JSON Schema for ${name}...`);

  try {
    const jsonSchema = z.toJSONSchema(schema, {
      target: 'draft-2020-12',
      unrepresentable: 'any',
      cycles: 'ref',
      reused: 'inline',
    });

    // Add schema metadata
    const schemaWithMeta = {
      $schema: 'https://json-schema.org/draft/2020-12/schema',
      $id: `https://onetimesecret.com/schemas/${name}.json`,
      title: name
        .split('-')
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' '),
      description: description || `Configuration schema for ${name}`,
      ...jsonSchema,
    };

    const outputPath = join(outputDir, `${name}.json`);
    writeFileSync(outputPath, JSON.stringify(schemaWithMeta, null, 2));
    console.log(`✓ Generated: ${outputPath}`);

    return schemaWithMeta;
  } catch (error) {
    console.error(`Error generating schema for ${name}:`, error);
    throw error;
  }
}

/**
 * Generate OpenAPI-compatible schema
 */
function generateOpenAPISchema(schema: z.ZodTypeAny, name: string, description?: string) {
  console.log(`Generating OpenAPI Schema for ${name}...`);

  try {
    const openAPISchema = z.toJSONSchema(schema, {
      target: 'draft-7', // OpenAPI uses draft-7
      unrepresentable: 'any',
      cycles: 'ref',
      reused: 'ref',
    });

    const schemaWithMeta = {
      title: name
        .split('-')
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' '),
      description: description || `OpenAPI schema for ${name}`,
      ...openAPISchema,
    };

    const outputPath = join(outputDir, `${name}.openapi.json`);
    writeFileSync(outputPath, JSON.stringify(schemaWithMeta, null, 2));
    console.log(`✓ Generated OpenAPI: ${outputPath}`);

    return schemaWithMeta;
  } catch (error) {
    console.error(`Error generating OpenAPI schema for ${name}:`, error);
    throw error;
  }
}

/**
 * Generate TypeScript definitions from schemas
 */
function generateTypeDefinitions() {
  console.log('Generating TypeScript definitions...');

  const typeDefinitions = `/**
 * Auto-generated TypeScript definitions from Zod schemas
 * Generated on: ${new Date().toISOString()}
 */

import { z } from 'zod';
import { systemSettingsSchema, staticConfigSchema } from '../src/schemas/config/settings';

// Inferred types from schemas
export type SystemSettings = z.infer<typeof systemSettingsSchema>;
export type StaticConfig = z.infer<typeof staticConfigSchema>;

// Combined configuration type
export type ApplicationConfig = {
  static?: StaticConfig;
  dynamic?: SystemSettings;
};

// Schema exports for runtime validation
export { systemSettingsSchema, staticConfigSchema };
`;

  const outputPath = join(outputDir, 'types.ts');
  writeFileSync(outputPath, typeDefinitions);
  console.log(`✓ Generated TypeScript definitions: ${outputPath}`);
}

/**
 * Main function to generate all schemas
 */
async function main() {
  console.log('🔧 Generating JSON Schemas from Zod configurations...\n');

  try {
    // Generate JSON Schema versions
    generateJSONSchema(
      systemSettingsSchema,
      'system-settings',
      'Dynamic system settings loaded from system_settings.defaults.yaml'
    );

    generateJSONSchema(
      staticConfigSchema,
      'static-config',
      'Static configuration settings loaded from config.yaml'
    );

    // Generate combined schema for validation
    const combinedSchema = z.object({
      static: staticConfigSchema.optional(),
      dynamic: systemSettingsSchema.optional(),
    });

    generateJSONSchema(
      combinedSchema,
      'combined-config',
      'Combined configuration schema for both static and dynamic settings'
    );

    // Generate OpenAPI versions
    generateOpenAPISchema(
      systemSettingsSchema,
      'system-settings',
      'Dynamic system settings for OpenAPI documentation'
    );

    generateOpenAPISchema(
      staticConfigSchema,
      'static-config',
      'Static configuration settings for OpenAPI documentation'
    );

    // Generate TypeScript definitions
    generateTypeDefinitions();

    console.log('\n✅ All JSON Schemas generated successfully!');
    console.log(`📁 Output directory: ${outputDir}`);
    console.log('\n📋 Generated files:');
    console.log('  • system-settings.json - JSON Schema for dynamic settings');
    console.log('  • static-config.json - JSON Schema for static settings');
    console.log('  • combined-config.json - Combined configuration schema');
    console.log('  • system-settings.openapi.json - OpenAPI schema for dynamic settings');
    console.log('  • static-config.openapi.json - OpenAPI schema for static settings');
    console.log('  • types.ts - TypeScript type definitions');
  } catch (error) {
    console.error('\n❌ Failed to generate JSON Schemas:', error);
    process.exit(1);
  }
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { generateJSONSchema, generateOpenAPISchema, generateTypeDefinitions, main };
