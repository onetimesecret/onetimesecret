#!/usr/bin/env npx tsx
/**
 * Validates test plan YAML files against the Zod v4 schema.
 *
 * Usage:
 *   npx tsx docs/test-plans/validate.ts                    # Validate all YAML files
 *   npx tsx docs/test-plans/validate.ts account-creation   # Validate specific file
 *   npx tsx docs/test-plans/validate.ts --help             # Show help
 */

import { readFileSync, readdirSync } from 'fs';
import { join, basename } from 'path';
import { parse } from 'yaml';
import { LLMTestFile } from './schema';

const TEST_PLANS_DIR = import.meta.dirname;

interface ValidationResult {
  file: string;
  valid: boolean;
  errors?: string[];
  testCount?: number;
}

function validateFile(filePath: string): ValidationResult {
  const fileName = basename(filePath);

  try {
    const content = readFileSync(filePath, 'utf-8');
    const data = parse(content);

    const result = LLMTestFile.safeParse(data);

    if (result.success) {
      return {
        file: fileName,
        valid: true,
        testCount: result.data.tests.length,
      };
    } else {
      // Format Zod v4 errors
      const errors = result.error.issues.map((issue) => {
        const path = issue.path.join('.');
        return `  ${path}: ${issue.message}`;
      });

      return {
        file: fileName,
        valid: false,
        errors,
      };
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      file: fileName,
      valid: false,
      errors: [`  Parse error: ${message}`],
    };
  }
}

function main() {
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    console.log(`
Validate test plan YAML files against schema.

Usage:
  npx tsx docs/test-plans/validate.ts                    # Validate all
  npx tsx docs/test-plans/validate.ts <name>             # Validate specific file
  npx tsx docs/test-plans/validate.ts --help             # Show help

Examples:
  npx tsx docs/test-plans/validate.ts account-creation
  npx tsx docs/test-plans/validate.ts subscription-upgrade.yaml
`);
    process.exit(0);
  }

  let files: string[];

  if (args.length > 0) {
    // Validate specific file(s)
    files = args.map((arg) => {
      const name = arg.endsWith('.yaml') ? arg : `${arg}.yaml`;
      return join(TEST_PLANS_DIR, name);
    });
  } else {
    // Validate all YAML files
    files = readdirSync(TEST_PLANS_DIR)
      .filter((f) => f.endsWith('.yaml'))
      .map((f) => join(TEST_PLANS_DIR, f));
  }

  console.log(`Validating ${files.length} test plan(s)...\n`);

  const results: ValidationResult[] = files.map(validateFile);

  // Print results
  let passCount = 0;
  let failCount = 0;
  let totalTests = 0;

  for (const result of results) {
    if (result.valid) {
      console.log(`✓ ${result.file} (${result.testCount} tests)`);
      passCount++;
      totalTests += result.testCount || 0;
    } else {
      console.log(`✗ ${result.file}`);
      result.errors?.forEach((err) => console.log(err));
      failCount++;
    }
  }

  // Summary
  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Total: ${passCount} passed, ${failCount} failed, ${totalTests} test cases`);

  process.exit(failCount > 0 ? 1 : 0);
}

main();
