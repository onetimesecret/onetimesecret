/**
 * Auto-Migration Runner
 *
 * Iterative, self-healing migration that runs until complete or max retries.
 *
 * Usage:
 *   npx tsx scripts/migration/auto-migrate.ts [--max-retries <n>] [--dry-run]
 *
 * Features:
 * - Runs migration phases iteratively
 * - Captures and analyzes errors
 * - Applies automatic fixes for common issues
 * - Retries failed phases
 * - Comprehensive logging
 * - Graceful abort with rollback option
 */

import { execSync, spawn } from 'child_process';
import * as fs from 'fs-extra';
import * as path from 'path';
import * as readline from 'readline';

const ROOT = path.resolve(__dirname, '../..');
const SRC = path.join(ROOT, 'src');
const BACKUP = path.join(ROOT, 'src.backup');
const LOG_FILE = path.join(ROOT, 'migration.log');

interface MigrationState {
  phase: number;
  attempt: number;
  errors: ErrorRecord[];
  fixes: string[];
  startTime: Date;
  completed: boolean;
}

interface ErrorRecord {
  phase: number;
  attempt: number;
  message: string;
  stack?: string;
  timestamp: Date;
}

interface FixResult {
  applied: boolean;
  description: string;
}

// ============================================================================
// Configuration
// ============================================================================

const MAX_RETRIES_PER_PHASE = 3;
const MAX_TOTAL_RETRIES = 10;
const PHASES = [
  { num: 1, name: 'Backup', canRetry: false },
  { num: 2, name: 'Create Directories', canRetry: true },
  { num: 3, name: 'Move Files', canRetry: true },
  { num: 4, name: 'Rewrite Imports', canRetry: true },
  { num: 5, name: 'Create New Files', canRetry: true },
  { num: 6, name: 'Validate', canRetry: true },
];

// ============================================================================
// Logging
// ============================================================================

function log(msg: string, level: 'info' | 'warn' | 'error' | 'success' = 'info') {
  const timestamp = new Date().toISOString();
  const prefix = {
    info: '📋',
    warn: '⚠️ ',
    error: '❌',
    success: '✅',
  }[level];

  const line = `[${timestamp}] ${prefix} ${msg}`;
  console.log(line);
  fs.appendFileSync(LOG_FILE, line + '\n');
}

function logPhase(phase: number, name: string, attempt: number) {
  const header = `\n${'═'.repeat(60)}\n Phase ${phase}: ${name} (Attempt ${attempt})\n${'═'.repeat(60)}`;
  console.log(header);
  fs.appendFileSync(LOG_FILE, header + '\n');
}

function logSeparator() {
  console.log('─'.repeat(60));
}

// ============================================================================
// Error Analysis & Fixes
// ============================================================================

interface ErrorPattern {
  pattern: RegExp;
  fix: (match: RegExpMatchArray, state: MigrationState) => Promise<FixResult>;
}

const ERROR_PATTERNS: ErrorPattern[] = [
  // Missing directory
  {
    pattern: /ENOENT.*no such file or directory.*'([^']+)'/i,
    fix: async (match) => {
      const dir = path.dirname(match[1]);
      if (dir.includes('src/apps') || dir.includes('src/shared')) {
        fs.ensureDirSync(dir);
        return { applied: true, description: `Created missing directory: ${dir}` };
      }
      return { applied: false, description: 'Cannot auto-create directory outside src/' };
    },
  },

  // File already exists at destination
  {
    pattern: /dest already exists.*'([^']+)'/i,
    fix: async (match) => {
      const dest = match[1];
      // Check if source and dest are identical
      const src = dest.replace('/apps/', '/views/').replace('/shared/', '/');
      if (fs.existsSync(src) && fs.existsSync(dest)) {
        const srcContent = fs.readFileSync(src, 'utf-8');
        const destContent = fs.readFileSync(dest, 'utf-8');
        if (srcContent === destContent) {
          fs.removeSync(src);
          return { applied: true, description: `Removed duplicate source: ${src}` };
        }
      }
      return { applied: false, description: 'Files differ - manual resolution needed' };
    },
  },

  // Import not found after move
  {
    pattern: /Cannot find module '(@\/[^']+)'/,
    fix: async (match) => {
      const importPath = match[1];
      log(`Unresolved import: ${importPath}`, 'warn');
      // This will be caught by the next import rewrite pass
      return { applied: false, description: `Import path needs manual mapping: ${importPath}` };
    },
  },

  // TypeScript error - property does not exist
  {
    pattern: /Property '(\w+)' does not exist on type/,
    fix: async () => {
      return { applied: false, description: 'Type error - likely needs code fix' };
    },
  },

  // Vue component not found
  {
    pattern: /Failed to resolve component: (\w+)/,
    fix: async (match) => {
      const component = match[1];
      log(`Missing component registration: ${component}`, 'warn');
      return { applied: false, description: `Component ${component} needs registration` };
    },
  },

  // Duplicate identifier
  {
    pattern: /Duplicate identifier '(\w+)'/,
    fix: async () => {
      return { applied: false, description: 'Duplicate export - needs manual resolution' };
    },
  },
];

async function analyzeAndFix(error: string, state: MigrationState): Promise<FixResult[]> {
  const results: FixResult[] = [];

  for (const { pattern, fix } of ERROR_PATTERNS) {
    const match = error.match(pattern);
    if (match) {
      try {
        const result = await fix(match, state);
        results.push(result);
        if (result.applied) {
          log(`Auto-fix applied: ${result.description}`, 'success');
          state.fixes.push(result.description);
        } else {
          log(`Cannot auto-fix: ${result.description}`, 'warn');
        }
      } catch (e) {
        log(`Fix attempt failed: ${(e as Error).message}`, 'error');
      }
    }
  }

  return results;
}

// ============================================================================
// Phase Execution
// ============================================================================

function runPhase(phase: number, dryRun: boolean): { success: boolean; output: string; error?: string } {
  const args = dryRun ? ['--dry-run', '--phase', String(phase)] : ['--phase', String(phase)];

  try {
    const output = execSync(
      `npx tsx scripts/migration/migrate.ts ${args.join(' ')}`,
      {
        cwd: ROOT,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
        timeout: 300000, // 5 minute timeout per phase
      }
    );
    return { success: true, output };
  } catch (e: any) {
    return {
      success: false,
      output: e.stdout || '',
      error: e.stderr || e.message,
    };
  }
}

// ============================================================================
// Validation Helpers
// ============================================================================

function runTypeCheck(): { success: boolean; errors: string[] } {
  try {
    execSync('pnpm run type-check', { cwd: ROOT, stdio: 'pipe' });
    return { success: true, errors: [] };
  } catch (e: any) {
    const output = e.stdout?.toString() || e.stderr?.toString() || '';
    const errors = output
      .split('\n')
      .filter((line: string) => line.includes('error TS'))
      .slice(0, 20); // Limit to first 20 errors
    return { success: false, errors };
  }
}

function runBuild(): { success: boolean; errors: string[] } {
  try {
    execSync('pnpm run build', { cwd: ROOT, stdio: 'pipe' });
    return { success: true, errors: [] };
  } catch (e: any) {
    const output = e.stdout?.toString() || e.stderr?.toString() || '';
    const errors = output.split('\n').filter((line: string) =>
      line.includes('error') || line.includes('Error')
    ).slice(0, 20);
    return { success: false, errors };
  }
}

// ============================================================================
// Interactive Prompts
// ============================================================================

async function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim().toLowerCase());
    });
  });
}

async function confirmContinue(state: MigrationState): Promise<'continue' | 'retry' | 'abort' | 'skip'> {
  console.log('\nOptions:');
  console.log('  c - Continue to next phase');
  console.log('  r - Retry current phase');
  console.log('  s - Skip current phase');
  console.log('  a - Abort and rollback');

  const answer = await prompt('Choice [c/r/s/a]: ');

  switch (answer) {
    case 'c': return 'continue';
    case 'r': return 'retry';
    case 's': return 'skip';
    case 'a': return 'abort';
    default: return 'continue';
  }
}

// ============================================================================
// Main Migration Loop
// ============================================================================

async function runMigration(options: { dryRun: boolean; maxRetries: number; unattended: boolean }) {
  const state: MigrationState = {
    phase: 1,
    attempt: 1,
    errors: [],
    fixes: [],
    startTime: new Date(),
    completed: false,
  };

  // Initialize log file
  fs.writeFileSync(LOG_FILE, `Migration started at ${state.startTime.toISOString()}\n`);
  fs.appendFileSync(LOG_FILE, `Options: ${JSON.stringify(options)}\n\n`);

  log('Starting auto-migration...', 'info');
  if (options.dryRun) {
    log('DRY RUN MODE - No changes will be made', 'warn');
  }
  if (options.unattended) {
    log('UNATTENDED MODE - Will auto-retry on failures', 'warn');
  }

  let totalRetries = 0;
  let consecutiveFailures = 0;

  while (state.phase <= PHASES.length && totalRetries < options.maxRetries) {
    const phaseConfig = PHASES[state.phase - 1];
    logPhase(state.phase, phaseConfig.name, state.attempt);

    const result = runPhase(state.phase, options.dryRun);

    if (result.success) {
      log(`Phase ${state.phase} completed successfully`, 'success');
      console.log(result.output);

      // Reset counters on success
      state.attempt = 1;
      consecutiveFailures = 0;
      state.phase++;

    } else {
      log(`Phase ${state.phase} failed`, 'error');
      console.log(result.output);
      if (result.error) {
        console.error(result.error);
      }

      // Record error
      state.errors.push({
        phase: state.phase,
        attempt: state.attempt,
        message: result.error || 'Unknown error',
        timestamp: new Date(),
      });

      consecutiveFailures++;
      totalRetries++;

      // Try to auto-fix
      if (result.error) {
        log('Analyzing error for auto-fix...', 'info');
        const fixes = await analyzeAndFix(result.error, state);
        const anyApplied = fixes.some((f) => f.applied);

        if (anyApplied && phaseConfig.canRetry && state.attempt < MAX_RETRIES_PER_PHASE) {
          log('Auto-fix applied, will retry phase', 'info');
          state.attempt++;
          continue;
        }
      }

      // Decide next action
      if (options.unattended) {
        // In unattended mode, retry if possible, otherwise skip
        if (phaseConfig.canRetry && state.attempt < MAX_RETRIES_PER_PHASE) {
          log(`Retrying phase ${state.phase} (attempt ${state.attempt + 1})`, 'warn');
          state.attempt++;
          continue;
        } else if (consecutiveFailures >= 3) {
          log('Too many consecutive failures, aborting', 'error');
          break;
        } else {
          log(`Skipping phase ${state.phase} after ${state.attempt} attempts`, 'warn');
          state.attempt = 1;
          state.phase++;
          continue;
        }
      } else {
        // Interactive mode - ask user
        const choice = await confirmContinue(state);

        switch (choice) {
          case 'continue':
            state.attempt = 1;
            state.phase++;
            break;
          case 'retry':
            state.attempt++;
            break;
          case 'skip':
            state.attempt = 1;
            state.phase++;
            break;
          case 'abort':
            log('Migration aborted by user', 'warn');
            await rollback();
            return;
        }
      }
    }
  }

  // Final validation
  if (state.phase > PHASES.length) {
    logSeparator();
    log('All phases completed, running final validation...', 'info');

    if (!options.dryRun) {
      const typeCheck = runTypeCheck();
      if (typeCheck.success) {
        log('Type check passed', 'success');
      } else {
        log('Type check failed with errors:', 'error');
        typeCheck.errors.forEach((e) => console.log(`  ${e}`));
      }

      const build = runBuild();
      if (build.success) {
        log('Build passed', 'success');
      } else {
        log('Build failed with errors:', 'error');
        build.errors.forEach((e) => console.log(`  ${e}`));
      }

      state.completed = typeCheck.success && build.success;
    } else {
      state.completed = true;
    }
  }

  // Summary
  logSeparator();
  console.log('\n📊 Migration Summary');
  console.log('═'.repeat(40));
  console.log(`Duration: ${Math.round((Date.now() - state.startTime.getTime()) / 1000)}s`);
  console.log(`Phases completed: ${state.phase - 1}/${PHASES.length}`);
  console.log(`Total retries: ${totalRetries}`);
  console.log(`Errors encountered: ${state.errors.length}`);
  console.log(`Auto-fixes applied: ${state.fixes.length}`);
  console.log(`Status: ${state.completed ? '✅ SUCCESS' : '❌ INCOMPLETE'}`);
  console.log(`Log file: ${LOG_FILE}`);

  if (state.fixes.length > 0) {
    console.log('\nAuto-fixes applied:');
    state.fixes.forEach((f) => console.log(`  • ${f}`));
  }

  if (state.errors.length > 0 && !state.completed) {
    console.log('\nUnresolved errors:');
    const uniqueErrors = [...new Set(state.errors.map((e) => e.message))];
    uniqueErrors.slice(0, 5).forEach((e) => console.log(`  • ${e.slice(0, 100)}...`));
  }

  if (!state.completed && !options.dryRun) {
    console.log('\n⚠️  Migration incomplete. Options:');
    console.log('  1. Review errors in migration.log');
    console.log('  2. Fix issues manually and re-run');
    console.log('  3. Rollback: npx tsx scripts/migration/migrate.ts --rollback');
  }
}

async function rollback() {
  log('Rolling back migration...', 'warn');

  if (!fs.existsSync(BACKUP)) {
    log('No backup found - cannot rollback', 'error');
    return;
  }

  try {
    fs.removeSync(SRC);
    fs.moveSync(BACKUP, SRC);
    log('Rollback complete', 'success');
  } catch (e) {
    log(`Rollback failed: ${(e as Error).message}`, 'error');
  }
}

// ============================================================================
// CLI
// ============================================================================

function parseArgs() {
  const args = process.argv.slice(2);
  return {
    dryRun: args.includes('--dry-run'),
    maxRetries: args.includes('--max-retries')
      ? parseInt(args[args.indexOf('--max-retries') + 1]) || MAX_TOTAL_RETRIES
      : MAX_TOTAL_RETRIES,
    unattended: args.includes('--unattended') || args.includes('-y'),
    rollback: args.includes('--rollback'),
    help: args.includes('--help') || args.includes('-h'),
  };
}

function printHelp() {
  console.log(`
Auto-Migration Runner

Usage:
  npx tsx scripts/migration/auto-migrate.ts [options]

Options:
  --dry-run        Preview changes without executing
  --unattended, -y Run without prompts (auto-retry/skip on failure)
  --max-retries N  Maximum total retries (default: ${MAX_TOTAL_RETRIES})
  --rollback       Restore from backup
  --help, -h       Show this help

Examples:
  # Interactive migration with prompts on failure
  npx tsx scripts/migration/auto-migrate.ts

  # Fully automated - retries failures, skips if stuck
  npx tsx scripts/migration/auto-migrate.ts --unattended

  # Preview what would happen
  npx tsx scripts/migration/auto-migrate.ts --dry-run

  # Restore original state
  npx tsx scripts/migration/auto-migrate.ts --rollback
`);
}

async function main() {
  const options = parseArgs();

  if (options.help) {
    printHelp();
    return;
  }

  if (options.rollback) {
    await rollback();
    return;
  }

  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║           Auto-Migration Runner                            ║');
  console.log('╚════════════════════════════════════════════════════════════╝');

  await runMigration(options);
}

main().catch((e) => {
  console.error('Fatal error:', e);
  process.exit(1);
});
