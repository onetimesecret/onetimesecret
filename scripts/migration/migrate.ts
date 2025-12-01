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
const BACKUP = path.join(ROOT, 'src.backup');

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
  logPhase(1, 'Create Backup');

  if (fs.existsSync(BACKUP)) {
    log(`⚠️  Backup already exists at ${BACKUP}`);
    log(`   Remove it first or use --rollback to restore`);
    if (!dryRun) {
      throw new Error('Backup exists - aborting to prevent data loss');
    }
  }

  if (dryRun) {
    log(`[DRY RUN] Would copy ${SRC} → ${BACKUP}`);
  } else {
    log(`Creating backup: ${SRC} → ${BACKUP}`);
    fs.copySync(SRC, BACKUP);
    log(`✅ Backup created`);
  }
}

// ============================================================================
// Phase 2: Create Directory Structure
// ============================================================================

const DIRECTORIES = [
  // Apps
  'apps/secret/conceal',
  'apps/secret/reveal',
  'apps/secret/support',
  'apps/secret/composables',
  'apps/secret/branding',
  'apps/secret/components/conceal',
  'apps/secret/components/reveal',
  'apps/secret/components/support',
  'apps/secret/components/incoming',
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

  // Add all .vue and .ts files in src/apps and src/shared
  const patterns = [
    path.join(SRC, 'apps/**/*.{ts,vue}'),
    path.join(SRC, 'shared/**/*.{ts,vue}'),
    path.join(SRC, 'router/**/*.ts'),
    path.join(SRC, 'stores/**/*.ts'),
    path.join(SRC, 'composables/**/*.ts'),
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
import { useIdentityStore } from '@/stores/identityStore';
import { useBranding } from '@/composables/useBranding';

export type ActorRole = 'CREATOR' | 'AUTH_RECIPIENT' | 'ANON_RECIPIENT';

export interface UIConfig {
  showBurnControl: boolean;
  showMarketingUpsell: boolean;
  headerAction: 'DASHBOARD_LINK' | 'SIGNUP_CTA';
}

export function useSecretContext() {
  const route = useRoute();
  const identity = useIdentityStore();
  const { domainStrategy, brand } = useBranding();

  const isAuthenticated = computed(() => identity.isAuthenticated);

  // Determine if viewer is the creator of this specific secret
  const isOwner = computed(() => {
    const creatorId = route.meta?.creatorId as string | undefined;
    return creatorId ? identity.custid === creatorId : false;
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
    return domainStrategy.value === 'custom'
      ? { mode: 'branded' as const, colors: brand.value?.colors }
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

  async function fetch() {
    state.value = 'loading';
    error.value = null;

    try {
      const data = await secretStore.fetchSecret(secretKey);

      if (!data) {
        state.value = 'unknown';
        return;
      }

      if (data.state === 'burned') {
        state.value = 'burned';
      } else if (data.state === 'expired') {
        state.value = 'expired';
      } else if (data.has_passphrase && !data.unlocked) {
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
      const data = await secretStore.revealSecret(secretKey, passphrase);
      payload.value = data.value;
      state.value = 'revealed';
    } catch (e) {
      error.value = e as Error;
      // Stay in current state on error
    }
  }

  async function burn() {
    try {
      await secretStore.burnSecret(secretKey);
      state.value = 'burned';
    } catch (e) {
      error.value = e as Error;
    }
  }

  return {
    state,
    payload,
    error,
    isTerminal,
    canReveal,
    fetch,
    reveal,
    burn,
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

    // App routers (stubs - to be filled with actual routes)
    'apps/secret/router.ts': `
import type { RouteRecordRaw } from 'vue-router';

export const routes: RouteRecordRaw[] = [
  // Conceal
  {
    path: '/',
    name: 'Homepage',
    component: () => import('./conceal/Homepage.vue'),
    meta: { layout: 'transactional' },
  },
  {
    path: '/incoming',
    name: 'IncomingForm',
    component: () => import('./conceal/IncomingForm.vue'),
    meta: { layout: 'transactional' },
  },

  // Reveal
  {
    path: '/secret/:secretKey',
    name: 'ShowSecret',
    component: () => import('./reveal/ShowSecret.vue'),
    meta: { layout: 'transactional' },
  },
  {
    path: '/private/:metadataKey',
    name: 'ShowMetadata',
    component: () => import('./reveal/ShowMetadata.vue'),
    meta: { layout: 'transactional' },
  },

  // Support
  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('./support/Feedback.vue'),
    meta: { layout: 'transactional' },
  },
];
`.trim(),

    'apps/workspace/router.ts': `
import type { RouteRecordRaw } from 'vue-router';

export const routes: RouteRecordRaw[] = [
  // Dashboard
  {
    path: '/dashboard',
    name: 'Dashboard',
    component: () => import('./dashboard/DashboardIndex.vue'),
    meta: { requiresAuth: true, layout: 'management' },
  },
  {
    path: '/recent',
    name: 'Recent',
    component: () => import('./dashboard/DashboardRecent.vue'),
    meta: { requiresAuth: true, layout: 'management' },
  },

  // Account
  {
    path: '/account',
    name: 'Account',
    component: () => import('./account/AccountIndex.vue'),
    meta: { requiresAuth: true, layout: 'management' },
  },

  // Billing
  {
    path: '/billing',
    name: 'Billing',
    component: () => import('./billing/BillingOverview.vue'),
    meta: { requiresAuth: true, layout: 'management' },
  },

  // Teams
  {
    path: '/teams',
    name: 'Teams',
    component: () => import('./teams/TeamsHub.vue'),
    meta: { requiresAuth: true, layout: 'management' },
  },

  // Domains
  {
    path: '/domains',
    name: 'Domains',
    component: () => import('./domains/DomainsList.vue'),
    meta: { requiresAuth: true, layout: 'management' },
  },
];
`.trim(),

    'apps/kernel/router.ts': `
import type { RouteRecordRaw } from 'vue-router';

export const routes: RouteRecordRaw[] = [
  {
    path: '/colonel',
    name: 'Colonel',
    component: () => import('./views/ColonelIndex.vue'),
    meta: { requiresAuth: true, requiresAdmin: true, layout: 'admin' },
  },
  {
    path: '/colonel/users',
    name: 'ColonelUsers',
    component: () => import('./views/ColonelUsers.vue'),
    meta: { requiresAuth: true, requiresAdmin: true, layout: 'admin' },
  },
  {
    path: '/colonel/secrets',
    name: 'ColonelSecrets',
    component: () => import('./views/ColonelSecrets.vue'),
    meta: { requiresAuth: true, requiresAdmin: true, layout: 'admin' },
  },
  {
    path: '/colonel/domains',
    name: 'ColonelDomains',
    component: () => import('./views/ColonelDomains.vue'),
    meta: { requiresAuth: true, requiresAdmin: true, layout: 'admin' },
  },
  {
    path: '/colonel/system',
    name: 'ColonelSystem',
    component: () => import('./views/ColonelSystem.vue'),
    meta: { requiresAuth: true, requiresAdmin: true, layout: 'admin' },
  },
];
`.trim(),

    'apps/session/router.ts': `
import type { RouteRecordRaw } from 'vue-router';

export const routes: RouteRecordRaw[] = [
  {
    path: '/signin',
    name: 'Login',
    component: () => import('./views/Login.vue'),
    meta: { layout: 'minimal', guestOnly: true },
  },
  {
    path: '/signup',
    name: 'Register',
    component: () => import('./views/Register.vue'),
    meta: { layout: 'minimal', guestOnly: true },
  },
  {
    path: '/forgot',
    name: 'PasswordResetRequest',
    component: () => import('./views/PasswordResetRequest.vue'),
    meta: { layout: 'minimal' },
  },
  {
    path: '/reset-password',
    name: 'PasswordReset',
    component: () => import('./views/PasswordReset.vue'),
    meta: { layout: 'minimal' },
  },
  {
    path: '/mfa-verify',
    name: 'MfaChallenge',
    component: () => import('./views/MfaChallenge.vue'),
    meta: { layout: 'minimal' },
  },
  {
    path: '/verify-account',
    name: 'VerifyAccount',
    component: () => import('./views/VerifyAccount.vue'),
    meta: { layout: 'minimal' },
  },
];
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
  console.log('\n🔄 Rolling back migration...');

  if (!fs.existsSync(BACKUP)) {
    console.error('❌ No backup found at', BACKUP);
    process.exit(1);
  }

  // Remove current src
  fs.removeSync(SRC);

  // Restore backup
  fs.moveSync(BACKUP, SRC);

  console.log('✅ Rollback complete - restored from backup');
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
      console.log('\nRun with --rollback to restore from backup');
    }
    process.exit(1);
  }
}

main();
