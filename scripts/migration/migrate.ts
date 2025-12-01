/**
 * Interaction Modes Migration Script
 *
 * Atomic migration from src/views + src/components to src/apps structure.
 *
 * Usage:
 *   npx tsx scripts/migration/migrate.ts [--dry-run] [--phase <n>]
 *
 * Options:
 *   --dry-run    Show what would be done without making changes
 *   --phase <n>  Run only phase n (1-6)
 *   --rollback   Restore from backup
 */

import { execSync } from 'child_process';
import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';
import { Project } from 'ts-morph';
import { fileMoves, FileMove } from './moves.js';
import { rewriteImports, PATH_MAPPINGS } from './imports.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '../..');
const SRC = path.join(ROOT, 'src');

interface MigrationOptions {
  dryRun: boolean;
  phase?: number;
  rollback: boolean;
}

function parseArgs(): MigrationOptions {
  const args = process.argv.slice(2);
  return {
    dryRun: args.includes('--dry-run'),
    phase: args.includes('--phase') ? parseInt(args[args.indexOf('--phase') + 1]) : undefined,
    rollback: args.includes('--rollback'),
  };
}

function log(msg: string, indent = 0) {
  console.log('  '.repeat(indent) + msg);
}

function logPhase(phase: number, name: string) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Phase ${phase}: ${name}`);
  console.log('='.repeat(60));
}

// ============================================================================
// Phase 1: Backup
// ============================================================================

function phase1Backup(dryRun: boolean) {
  logPhase(1, 'Skip Backup (use git to rollback)');
  log(`ℹ️  Backup skipped - use 'git checkout -- src/' to rollback`);
}

// ============================================================================
// Phase 2: Create Directory Structure
// ============================================================================

const DIRECTORIES = [
  // Apps
  'apps/secret/conceal',
  'apps/secret/reveal',
  'apps/secret/reveal/branded',
  'apps/secret/reveal/canonical',
  'apps/secret/support',
  'apps/secret/composables',
  'apps/secret/branding',
  'apps/secret/components/conceal',
  'apps/secret/components/reveal',
  'apps/secret/components/support',
  'apps/secret/components/incoming',
  'apps/secret/components/branded',
  'apps/secret/components/canonical',
  'apps/workspace/dashboard',
  'apps/workspace/account/region',
  'apps/workspace/account/settings',
  'apps/workspace/billing',
  'apps/workspace/teams',
  'apps/workspace/domains',
  'apps/workspace/components/dashboard',
  'apps/workspace/components/account',
  'apps/workspace/components/billing',
  'apps/workspace/components/teams',
  'apps/workspace/components/organizations',
  'apps/workspace/components/domains',
  'apps/kernel/views',
  'apps/kernel/components',
  'apps/session/views',
  'apps/session/logic',
  'apps/session/components',
  // Shared
  'shared/components/base',
  'shared/components/ui',
  'shared/components/forms',
  'shared/components/modals',
  'shared/components/errors',
  'shared/components/common',
  'shared/components/icons',
  'shared/components/logos',
  'shared/components/layout',
  'shared/components/navigation',
  'shared/components/ctas',
  'shared/components/closet',
  'shared/layouts',
  'shared/branding/api',
  'shared/composables',
  'shared/stores',
];

function phase2CreateDirectories(dryRun: boolean) {
  logPhase(2, 'Create Directory Structure');

  for (const dir of DIRECTORIES) {
    const fullPath = path.join(SRC, dir);
    if (dryRun) {
      log(`[DRY RUN] mkdir -p ${dir}`);
    } else {
      fs.ensureDirSync(fullPath);
      log(`✅ Created ${dir}`);
    }
  }
}

// ============================================================================
// Phase 3: Move Files
// ============================================================================

function phase3MoveFiles(dryRun: boolean) {
  logPhase(3, 'Move Files');

  const moves = fileMoves();
  let moved = 0;
  let skipped = 0;
  let deleted = 0;

  for (const move of moves) {
    const srcPath = path.join(SRC, move.from);
    const destPath = move.to ? path.join(SRC, move.to) : null;

    if (!fs.existsSync(srcPath)) {
      log(`⚠️  Source not found: ${move.from}`, 1);
      skipped++;
      continue;
    }

    if (move.action === 'delete') {
      if (dryRun) {
        log(`[DRY RUN] DELETE ${move.from}`);
      } else {
        fs.removeSync(srcPath);
        log(`🗑️  Deleted ${move.from}`);
      }
      deleted++;
      continue;
    }

    if (!destPath) {
      log(`⚠️  No destination for: ${move.from}`, 1);
      skipped++;
      continue;
    }

    if (dryRun) {
      log(`[DRY RUN] ${move.from} → ${move.to}`);
    } else {
      fs.ensureDirSync(path.dirname(destPath));
      if (move.action === 'move' || move.action === 'rename') {
        fs.moveSync(srcPath, destPath, { overwrite: true });
        log(`📦 ${move.from} → ${move.to}`);
      } else if (move.action === 'copy') {
        fs.copySync(srcPath, destPath);
        log(`📋 ${move.from} → ${move.to} (copy)`);
      }
    }
    moved++;
  }

  log(`\nSummary: ${moved} moved, ${deleted} deleted, ${skipped} skipped`);
}

// ============================================================================
// Phase 4: Rewrite Imports (AST-based)
// ============================================================================

function phase4RewriteImports(dryRun: boolean) {
  logPhase(4, 'Rewrite Imports (AST-based)');

  const project = new Project({
    tsConfigFilePath: path.join(ROOT, 'tsconfig.json'),
    skipAddingFilesFromTsConfig: true,
  });

  // Add all .vue and .ts files that may have imports to rewrite
  const patterns = [
    path.join(SRC, '*.{ts,vue}'),           // Root files (App.vue, main.ts)
    path.join(SRC, 'apps/**/*.{ts,vue}'),
    path.join(SRC, 'shared/**/*.{ts,vue}'),
    path.join(SRC, 'router/**/*.ts'),
    path.join(SRC, 'stores/**/*.ts'),
    path.join(SRC, 'composables/**/*.ts'),
    path.join(SRC, 'schemas/**/*.ts'),
    path.join(SRC, 'types/**/*.ts'),
    path.join(SRC, 'utils/**/*.ts'),
    path.join(SRC, 'plugins/**/*.ts'),
  ];

  for (const pattern of patterns) {
    project.addSourceFilesAtPaths(pattern);
  }

  const sourceFiles = project.getSourceFiles();
  log(`Found ${sourceFiles.length} files to process`);

  let filesModified = 0;
  let importsRewritten = 0;

  for (const sourceFile of sourceFiles) {
    const result = rewriteImports(sourceFile, PATH_MAPPINGS);
    if (result.modified) {
      filesModified++;
      importsRewritten += result.count;
      if (dryRun) {
        log(`[DRY RUN] Would rewrite ${result.count} imports in ${sourceFile.getBaseName()}`);
      } else {
        log(`✏️  Rewrote ${result.count} imports in ${sourceFile.getBaseName()}`);
      }
    }
  }

  if (!dryRun) {
    project.saveSync();
  }

  log(`\nSummary: ${filesModified} files modified, ${importsRewritten} imports rewritten`);
}

// ============================================================================
// Phase 5: Create New Files
// ============================================================================

function phase5CreateNewFiles(dryRun: boolean) {
  logPhase(5, 'Create New Files');

  const newFiles: Record<string, string> = {
    // useSecretContext composable
    'apps/secret/composables/useSecretContext.ts': `
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useProductIdentity } from '@/stores/identityStore';
import { useAuthStore } from '@/stores/authStore';

export type ActorRole = 'CREATOR' | 'AUTH_RECIPIENT' | 'ANON_RECIPIENT';

export interface UIConfig {
  showBurnControl: boolean;
  showMarketingUpsell: boolean;
  headerAction: 'DASHBOARD_LINK' | 'SIGNUP_CTA';
}

export function useSecretContext() {
  const route = useRoute();
  const identity = useProductIdentity();
  const auth = useAuthStore();

  const isAuthenticated = computed(() => auth.isLoggedIn);

  // Determine if viewer is the creator of this specific secret
  const isOwner = computed(() => {
    const creatorId = route.meta?.creatorId as string | undefined;
    return creatorId ? auth.custid === creatorId : false;
  });

  const actorRole = computed<ActorRole>(() => {
    if (isOwner.value) return 'CREATOR';
    if (isAuthenticated.value) return 'AUTH_RECIPIENT';
    return 'ANON_RECIPIENT';
  });

  const uiConfig = computed<UIConfig>(() => {
    switch (actorRole.value) {
      case 'CREATOR':
        return {
          showBurnControl: true,
          showMarketingUpsell: false,
          headerAction: 'DASHBOARD_LINK',
        };
      case 'AUTH_RECIPIENT':
        return {
          showBurnControl: false,
          showMarketingUpsell: false,
          headerAction: 'DASHBOARD_LINK',
        };
      case 'ANON_RECIPIENT':
      default:
        return {
          showBurnControl: false,
          showMarketingUpsell: true,
          headerAction: 'SIGNUP_CTA',
        };
    }
  });

  const theme = computed(() => {
    return identity.domainStrategy === 'custom'
      ? { mode: 'branded' as const, colors: identity.brand?.primary_color }
      : { mode: 'canonical' as const, colors: null };
  });

  return {
    actorRole,
    uiConfig,
    theme,
    isAuthenticated,
    isOwner,
  };
}
`.trim(),

    // useHomepageMode composable
    'apps/secret/composables/useHomepageMode.ts': `
import { computed } from 'vue';
import { WindowService } from '@/services/window.service';

export type HomepageMode = 'open' | 'internal' | 'external';

export function useHomepageMode() {
  const mode = computed<HomepageMode>(() => {
    return (WindowService.get('homepage_mode') as HomepageMode) || 'open';
  });

  const isDisabled = computed(() => mode.value === 'external');
  const isInternal = computed(() => mode.value === 'internal');
  const isOpen = computed(() => mode.value === 'open');

  const options = computed(() => ({
    showInternalWarning: isInternal.value,
    allowCreation: !isDisabled.value,
  }));

  return {
    mode,
    isDisabled,
    isInternal,
    isOpen,
    options,
  };
}
`.trim(),

    // useSecretLifecycle composable
    'apps/secret/composables/useSecretLifecycle.ts': `
import { ref, computed } from 'vue';
import { useSecretStore } from '@/stores/secretStore';

export type SecretState =
  | 'idle'
  | 'loading'
  | 'passphrase'
  | 'ready'
  | 'revealed'
  | 'burned'
  | 'expired'
  | 'unknown';

export function useSecretLifecycle(secretKey: string) {
  const secretStore = useSecretStore();
  const state = ref<SecretState>('idle');
  const payload = ref<string | null>(null);
  const error = ref<Error | null>(null);

  const isTerminal = computed(() =>
    ['burned', 'expired', 'unknown'].includes(state.value)
  );

  const canReveal = computed(() =>
    ['ready', 'passphrase'].includes(state.value)
  );

  async function load() {
    state.value = 'loading';
    error.value = null;

    try {
      const data = await secretStore.fetch(secretKey);

      if (!data?.record) {
        state.value = 'unknown';
        return;
      }

      const record = data.record;
      if (record.state === 'burned') {
        state.value = 'burned';
      } else if (record.state === 'viewed') {
        state.value = 'revealed';
      } else if (record.has_passphrase) {
        state.value = 'passphrase';
      } else {
        state.value = 'ready';
      }
    } catch (e) {
      error.value = e as Error;
      state.value = 'unknown';
    }
  }

  async function reveal(passphrase?: string) {
    if (!canReveal.value) return;

    try {
      await secretStore.reveal(secretKey, passphrase);
      payload.value = secretStore.record?.secret_value ?? null;
      state.value = 'revealed';
    } catch (e) {
      error.value = e as Error;
      // Stay in current state on error
    }
  }

  return {
    state,
    payload,
    error,
    isTerminal,
    canReveal,
    load,
    reveal,
  };
}
`.trim(),

    // Traffic controller
    'apps/session/logic/traffic-controller.ts': `
import { RouteLocationNormalized } from 'vue-router';

export interface TrafficDecision {
  redirect: string | null;
  reason: string;
}

/**
 * Determines where to redirect after authentication events.
 */
export function afterLogin(
  from: RouteLocationNormalized,
  intendedDestination?: string
): TrafficDecision {
  // Priority 1: Explicit return_to parameter
  const returnTo = from.query.return_to as string | undefined;
  if (returnTo && isValidReturnPath(returnTo)) {
    return { redirect: returnTo, reason: 'return_to parameter' };
  }

  // Priority 2: Intended destination (stored before auth redirect)
  if (intendedDestination && isValidReturnPath(intendedDestination)) {
    return { redirect: intendedDestination, reason: 'stored destination' };
  }

  // Priority 3: Default to dashboard
  return { redirect: '/dashboard', reason: 'default' };
}

export function afterLogout(): TrafficDecision {
  return { redirect: '/', reason: 'logout default' };
}

export function afterSignup(): TrafficDecision {
  return { redirect: '/dashboard', reason: 'new account' };
}

function isValidReturnPath(path: string): boolean {
  // Must be relative path, no protocol
  if (path.includes('://')) return false;
  if (!path.startsWith('/')) return false;
  // Block auth pages to prevent loops
  if (path.startsWith('/signin') || path.startsWith('/signup')) return false;
  return true;
}
`.trim(),

    // App routers - placeholder files for future route organization
    // Routes are currently defined in src/router/*.routes.ts
    'apps/secret/router.ts': `
/**
 * Secret App Routes (Placeholder)
 *
 * Routes for this app are currently defined in:
 * - src/router/public.routes.ts (homepage, feedback)
 * - src/router/secret.routes.ts (reveal)
 * - src/router/incoming.routes.ts (conceal via API)
 * - src/router/metadata.routes.ts (metadata views)
 *
 * TODO: Consolidate routes here when refactoring router architecture
 */
export {};
`.trim(),

    'apps/workspace/router.ts': `
/**
 * Workspace App Routes (Placeholder)
 *
 * Routes for this app are currently defined in:
 * - src/router/dashboard.routes.ts
 * - src/router/account.routes.ts
 * - src/router/billing.routes.ts
 * - src/router/teams.routes.ts
 *
 * TODO: Consolidate routes here when refactoring router architecture
 */
export {};
`.trim(),

    'apps/kernel/router.ts': `
/**
 * Kernel App Routes (Placeholder)
 *
 * Routes for this app are currently defined in:
 * - src/router/colonel.routes.ts
 *
 * TODO: Consolidate routes here when refactoring router architecture
 */
export {};
`.trim(),

    'apps/session/router.ts': `
/**
 * Session App Routes (Placeholder)
 *
 * Routes for this app are currently defined in:
 * - src/router/auth.routes.ts
 *
 * TODO: Consolidate routes here when refactoring router architecture
 */
export {};
`.trim(),
  };

  for (const [filePath, content] of Object.entries(newFiles)) {
    const fullPath = path.join(SRC, filePath);
    if (dryRun) {
      log(`[DRY RUN] Would create ${filePath}`);
    } else {
      fs.ensureDirSync(path.dirname(fullPath));
      fs.writeFileSync(fullPath, content);
      log(`✨ Created ${filePath}`);
    }
  }
}

// ============================================================================
// Phase 6: Validate
// ============================================================================

function phase6Validate(dryRun: boolean) {
  logPhase(6, 'Validate');

  if (dryRun) {
    log('[DRY RUN] Would run: pnpm run type-check');
    log('[DRY RUN] Would run: pnpm run build');
    return;
  }

  try {
    log('Running type-check...');
    execSync('pnpm run type-check', { cwd: ROOT, stdio: 'inherit' });
    log('✅ Type check passed');
  } catch (e) {
    log('❌ Type check failed');
    throw new Error('Type check failed - see errors above');
  }

  try {
    log('Running build...');
    execSync('pnpm run build', { cwd: ROOT, stdio: 'inherit' });
    log('✅ Build passed');
  } catch (e) {
    log('❌ Build failed');
    throw new Error('Build failed - see errors above');
  }

  log('\n🎉 Migration completed successfully!');
}

// ============================================================================
// Rollback
// ============================================================================

function rollback() {
  console.log('\n🔄 Rolling back migration via git...');
  console.log('Run: git checkout -- src/');
  console.log('Or:  git restore src/');
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const options = parseArgs();

  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║       Interaction Modes Migration Script                   ║');
  console.log('╚════════════════════════════════════════════════════════════╝');

  if (options.dryRun) {
    console.log('\n🔍 DRY RUN MODE - No changes will be made\n');
  }

  if (options.rollback) {
    rollback();
    return;
  }

  const phases = [
    () => phase1Backup(options.dryRun),
    () => phase2CreateDirectories(options.dryRun),
    () => phase3MoveFiles(options.dryRun),
    () => phase4RewriteImports(options.dryRun),
    () => phase5CreateNewFiles(options.dryRun),
    () => phase6Validate(options.dryRun),
  ];

  try {
    for (let i = 0; i < phases.length; i++) {
      if (options.phase && options.phase !== i + 1) continue;
      phases[i]();
    }
  } catch (e) {
    console.error('\n❌ Migration failed:', (e as Error).message);
    if (!options.dryRun) {
      console.log('\nRollback with: git checkout -- src/');
    }
    process.exit(1);
  }
}

main();
