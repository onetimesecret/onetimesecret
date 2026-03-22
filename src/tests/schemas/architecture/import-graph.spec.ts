// src/tests/schemas/architecture/import-graph.spec.ts
//
// Import graph integrity tests for the schema refactoring work.
// Verifies the contract -> shapes -> api layering is correctly followed.
//
// Architecture:
//   contracts/   <- canonical field definitions, no transforms
//   shapes/v*/   <- version-specific transforms (extends contracts)
//   api/v*/responses/ <- API envelope wrappers (imports shapes)

import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync, statSync, existsSync } from 'fs';
import { join, relative } from 'path';

const SRC_DIR = join(process.cwd(), 'src', 'schemas');

// -----------------------------------------------------------------------------
// Utility Functions
// -----------------------------------------------------------------------------

/**
 * Recursively find all .ts files in a directory
 */
function findTsFiles(dir: string): string[] {
  if (!existsSync(dir)) return [];

  const results: string[] = [];
  const entries = readdirSync(dir);

  for (const entry of entries) {
    const fullPath = join(dir, entry);
    const stat = statSync(fullPath);

    if (stat.isDirectory()) {
      results.push(...findTsFiles(fullPath));
    } else if (entry.endsWith('.ts') && !entry.endsWith('.spec.ts')) {
      results.push(fullPath);
    }
  }

  return results;
}

/**
 * Extract import statements from a TypeScript file
 */
function extractImports(filePath: string): string[] {
  const content = readFileSync(filePath, 'utf-8');
  const importRegex = /import\s+(?:[\s\S]*?from\s+)?['"]([^'"]+)['"]/g;
  const imports: string[] = [];
  let match;

  while ((match = importRegex.exec(content)) !== null) {
    imports.push(match[1]);
  }

  return imports;
}

/**
 * Get relative path from src/schemas directory
 */
function getRelativePath(filePath: string): string {
  return relative(SRC_DIR, filePath);
}

// -----------------------------------------------------------------------------
// Test: API Response directories exist and have files
// -----------------------------------------------------------------------------

describe('API Response Directory Structure', () => {
  const apiVersions = ['v1', 'v2', 'v3'];

  it.each(apiVersions)('api/%s/responses directory exists', (version) => {
    const dir = join(SRC_DIR, 'api', version, 'responses');
    expect(existsSync(dir)).toBe(true);
  });

  it.each(apiVersions)('api/%s/responses has TypeScript files', (version) => {
    const dir = join(SRC_DIR, 'api', version, 'responses');
    const files = findTsFiles(dir);
    expect(files.length).toBeGreaterThan(0);
  });

  it.each(apiVersions)('api/%s/responses has registry.ts', (version) => {
    const registryPath = join(SRC_DIR, 'api', version, 'responses', 'registry.ts');
    expect(existsSync(registryPath)).toBe(true);
  });
});

// -----------------------------------------------------------------------------
// Test: Shapes directories exist and have files
// -----------------------------------------------------------------------------

describe('Shapes Directory Structure', () => {
  const shapeVersions = ['v1', 'v2', 'v3'];

  it.each(shapeVersions)('shapes/%s directory exists', (version) => {
    const dir = join(SRC_DIR, 'shapes', version);
    expect(existsSync(dir)).toBe(true);
  });

  it.each(shapeVersions)('shapes/%s has TypeScript files', (version) => {
    const dir = join(SRC_DIR, 'shapes', version);
    const files = findTsFiles(dir);
    expect(files.length).toBeGreaterThan(0);
  });
});

// -----------------------------------------------------------------------------
// Test: Contracts directory exists
// -----------------------------------------------------------------------------

describe('Contracts Directory Structure', () => {
  it('contracts directory exists', () => {
    const dir = join(SRC_DIR, 'contracts');
    expect(existsSync(dir)).toBe(true);
  });

  it('contracts has TypeScript files', () => {
    const dir = join(SRC_DIR, 'contracts');
    const files = findTsFiles(dir);
    expect(files.length).toBeGreaterThan(0);
  });
});

// -----------------------------------------------------------------------------
// Test: Contracts should NOT import from shapes or api (dependency inversion)
// -----------------------------------------------------------------------------

describe('Contracts Independence (no upstream imports)', () => {
  const contractsDir = join(SRC_DIR, 'contracts');
  const contractFiles = findTsFiles(contractsDir);

  if (contractFiles.length === 0) {
    it.skip('no contract files to test', () => {});
  } else {
    it.each(contractFiles.map((f) => [getRelativePath(f), f]))(
      '%s does not import from shapes or api',
      (_, file) => {
        const imports = extractImports(file as string);

        const violatingImports = imports.filter(
          (imp) =>
            imp.includes('/shapes/') ||
            imp.includes('/api/') ||
            imp.includes('@/schemas/shapes') ||
            imp.includes('@/schemas/api')
        );

        expect(violatingImports).toEqual([]);
      }
    );
  }
});

// -----------------------------------------------------------------------------
// Test: Transform usage patterns
// -----------------------------------------------------------------------------

describe('Transform Usage Patterns', () => {
  it('V2 shapes use fromString transforms', () => {
    const v2Dir = join(SRC_DIR, 'shapes', 'v2');
    const files = findTsFiles(v2Dir);
    const filesWithTransforms = files.filter((file) => {
      const content = readFileSync(file, 'utf-8');
      return (
        content.includes('transforms.fromString') ||
        content.includes('fromString.')
      );
    });

    // V2 should use string transforms for Redis-encoded values
    expect(filesWithTransforms.length).toBeGreaterThan(0);
  });

  it('V3 shapes use fromNumber transforms for timestamps', () => {
    const v3Dir = join(SRC_DIR, 'shapes', 'v3');
    const files = findTsFiles(v3Dir);
    const filesWithTransforms = files.filter((file) => {
      const content = readFileSync(file, 'utf-8');
      return (
        content.includes('transforms.fromNumber') ||
        content.includes('fromNumber.')
      );
    });

    // V3 should use number transforms for native JSON types
    expect(filesWithTransforms.length).toBeGreaterThan(0);
  });

  it('Contracts do NOT use transforms (pure types only)', () => {
    const contractsDir = join(SRC_DIR, 'contracts');
    const files = findTsFiles(contractsDir);
    const filesWithTransforms = files.filter((file) => {
      const content = readFileSync(file, 'utf-8');
      return content.includes('@/schemas/transforms');
    });

    // Contracts should define pure types, no transforms
    expect(filesWithTransforms).toEqual([]);
  });
});

// -----------------------------------------------------------------------------
// Test: Registry completeness
// -----------------------------------------------------------------------------

describe('Response Registry Completeness', () => {
  const registryFiles = [
    { version: 'v1', path: join(SRC_DIR, 'api', 'v1', 'responses', 'registry.ts') },
    { version: 'v2', path: join(SRC_DIR, 'api', 'v2', 'responses', 'registry.ts') },
    { version: 'v3', path: join(SRC_DIR, 'api', 'v3', 'responses', 'registry.ts') },
  ];

  it.each(registryFiles)(
    '$version registry exports responseSchemas object',
    ({ path }) => {
      const content = readFileSync(path, 'utf-8');
      expect(content).toContain('export const responseSchemas');
      expect(content).toContain('} as const');
    }
  );

  it.each(registryFiles)(
    '$version registry exports ResponseTypes type',
    ({ path }) => {
      const content = readFileSync(path, 'utf-8');
      expect(content).toContain('export type ResponseTypes');
    }
  );
});

// -----------------------------------------------------------------------------
// Test: V2/V3 shapes import from contracts (migration verification)
// -----------------------------------------------------------------------------

describe('Shapes Contract Import Audit', () => {
  // These shape files SHOULD import from contracts
  const expectedContractImporters = [
    { path: 'shapes/v2/customer.ts', name: 'V2 customer' },
    { path: 'shapes/v3/customer.ts', name: 'V3 customer' },
    { path: 'shapes/v3/organization.ts', name: 'V3 organization' },
    { path: 'shapes/v3/receipt.ts', name: 'V3 receipt' },
    { path: 'shapes/v3/secret.ts', name: 'V3 secret' },
    { path: 'shapes/v3/feedback.ts', name: 'V3 feedback' },
    { path: 'shapes/v3/custom-domain.ts', name: 'V3 custom-domain' },
    { path: 'shapes/v3/organization-membership.ts', name: 'V3 organization-membership' },
  ];

  for (const { path, name } of expectedContractImporters) {
    const fullPath = join(SRC_DIR, path);

    if (existsSync(fullPath)) {
      it(`${name} imports from contracts`, () => {
        const imports = extractImports(fullPath);
        const contractImports = imports.filter(
          (imp) =>
            imp.includes('/contracts') || imp.includes('@/schemas/contracts')
        );
        expect(contractImports.length).toBeGreaterThan(0);
      });
    } else {
      it.skip(`${name} file not found (${path})`, () => {});
    }
  }
});

// -----------------------------------------------------------------------------
// Test: transforms module exists and exports expected transforms
// -----------------------------------------------------------------------------

describe('Transforms Module', () => {
  const transformsPath = join(SRC_DIR, 'transforms.ts');

  it('transforms.ts exists', () => {
    expect(existsSync(transformsPath)).toBe(true);
  });

  it('exports fromString transforms', () => {
    const content = readFileSync(transformsPath, 'utf-8');
    expect(content).toContain('fromString:');
    expect(content).toContain('boolean:');
    expect(content).toContain('number:');
    expect(content).toContain('date:');
    expect(content).toContain('dateNullable:');
  });

  it('exports fromNumber transforms', () => {
    const content = readFileSync(transformsPath, 'utf-8');
    expect(content).toContain('fromNumber:');
    expect(content).toContain('toDate:');
    expect(content).toContain('toDateNullable:');
    expect(content).toContain('toDateOptional:');
    expect(content).toContain('toDateNullish:');
  });
});
