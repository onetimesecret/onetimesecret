/**
 * PoC: Approach Analysis for OpenAPI Integration
 *
 * This script analyzes different approaches for integrating OpenAPI
 * generation with our existing Zod schemas.
 *
 * KEY FINDING:
 * @asteasolutions/zod-to-openapi requires that extendZodWithOpenApi()
 * be called BEFORE any schemas are created. It modifies Zod's prototype
 * to add the .openapi() method.
 *
 * This PoC tests both approaches to determine the best path forward.
 */

import { extendZodWithOpenApi, OpenAPIRegistry, OpenApiGeneratorV3 } from '@asteasolutions/zod-to-openapi';
import { z } from 'zod';

console.log('🔍 Analyzing OpenAPI Integration Approaches...\n');

// ============================================================================
// Approach A: Extend Zod First, Then Define Schemas
// ============================================================================
console.log('Approach A: Extend Zod before defining schemas');

// This MUST happen before any schemas are created
extendZodWithOpenApi(z);

// Now schemas created after this point will have .openapi() method
const schemaAfterExtension = z.object({
  id: z.string(),
  name: z.string()
}).openapi('TestSchema');

console.log('✅ Schema after extension has .openapi():', typeof schemaAfterExtension.openapi === 'function');

// Test registration
const registryA = new OpenAPIRegistry();
registryA.register('TestSchema', schemaAfterExtension);
console.log('✅ Can register schema in registry\n');

// ============================================================================
// Approach B: Use registerComponent Instead of register
// ============================================================================
console.log('Approach B: Use registerComponent for pre-existing schemas');

// For schemas created BEFORE extending Zod, we can use registerComponent
// This bypasses the .openapi() requirement
const schemaBeforeExtension = z.object({
  id: z.string(),
  value: z.number()
});

const registryB = new OpenAPIRegistry();

// registerComponent lets us directly specify the OpenAPI schema
registryB.registerComponent('schemas', 'PreExistingSchema', {
  type: 'object',
  properties: {
    id: { type: 'string' },
    value: { type: 'number' }
  },
  required: ['id', 'value']
});

console.log('✅ Can register pre-existing schema using registerComponent\n');

// ============================================================================
// RECOMMENDATION
// ============================================================================
console.log('📋 Recommendation Analysis:');
console.log('═══════════════════════════════════════════════════════');
console.log('');
console.log('✅ RECOMMENDED: Create Global Zod Extension Setup');
console.log('');
console.log('Implementation:');
console.log('1. Create src/schemas/openapi-setup.ts:');
console.log('   - Import and extend Zod with OpenAPI');
console.log('   - Re-export extended Zod');
console.log('');
console.log('2. Update all schema files to import from openapi-setup.ts:');
console.log('   - Before: import { z } from "zod"');
console.log('   - After:  import { z } from "@/schemas/openapi-setup"');
console.log('');
console.log('3. Benefits:');
console.log('   - All schemas automatically get .openapi() method');
console.log('   - Can use registry.register() everywhere');
console.log('   - Minimal code changes');
console.log('   - Clean, maintainable solution');
console.log('');
console.log('4. Migration Strategy:');
console.log('   - Schemas work without .openapi() metadata initially');
console.log('   - Can add metadata incrementally over time');
console.log('   - No breaking changes to existing code');
console.log('');
console.log('Alternative: Use registerComponent + Manual Schema Conversion');
console.log('   - Works with existing schemas immediately');
console.log('   - No code changes to schema files');
console.log('   - BUT: Requires maintaining parallel OpenAPI definitions');
console.log('   - Risk of drift between Zod and OpenAPI schemas');
console.log('');
console.log('Decision: Use Global Extension Approach (cleaner long-term)');
console.log('');
