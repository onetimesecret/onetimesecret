/**
 * AST-based import rewriting using ts-morph.
 *
 * This handles:
 * - Import declarations: import X from '@/views/...'
 * - Dynamic imports: () => import('@/views/...')
 * - Type imports: import type { X } from '@/views/...'
 */

import { SourceFile, SyntaxKind } from 'ts-morph';

export interface PathMapping {
  from: RegExp;
  to: string;
}

/**
 * Path mappings for import rewriting.
 * Order matters - more specific patterns should come first.
 */
export const PATH_MAPPINGS: PathMapping[] = [
  // Views → Apps
  { from: /^@\/views\/secrets\/branded\//, to: '@/apps/secret/reveal/' },
  { from: /^@\/views\/secrets\/canonical\//, to: '@/apps/secret/reveal/' },
  { from: /^@\/views\/secrets\//, to: '@/apps/secret/reveal/' },
  { from: /^@\/views\/incoming\//, to: '@/apps/secret/conceal/' },
  { from: /^@\/views\/dashboard\/Dashboard(Domain.*)/, to: '@/apps/workspace/domains/$1' },
  { from: /^@\/views\/dashboard\//, to: '@/apps/workspace/dashboard/' },
  { from: /^@\/views\/account\/region\//, to: '@/apps/workspace/account/region/' },
  { from: /^@\/views\/account\/settings\//, to: '@/apps/workspace/account/settings/' },
  { from: /^@\/views\/account\//, to: '@/apps/workspace/account/' },
  { from: /^@\/views\/billing\//, to: '@/apps/workspace/billing/' },
  { from: /^@\/views\/teams\//, to: '@/apps/workspace/teams/' },
  { from: /^@\/views\/colonel\//, to: '@/apps/kernel/views/' },
  { from: /^@\/views\/auth\/Signin\.vue$/, to: '@/apps/session/views/Login.vue' },
  { from: /^@\/views\/auth\/Signup\.vue$/, to: '@/apps/session/views/Register.vue' },
  { from: /^@\/views\/auth\/MfaVerify\.vue$/, to: '@/apps/session/views/MfaChallenge.vue' },
  { from: /^@\/views\/auth\//, to: '@/apps/session/views/' },
  { from: /^@\/views\/errors\//, to: '@/shared/components/errors/' },
  { from: /^@\/views\/HomepageContainer\.vue$/, to: '@/apps/secret/conceal/Homepage.vue' },
  { from: /^@\/views\/Homepage\.vue$/, to: '@/apps/secret/conceal/Homepage.vue' },
  { from: /^@\/views\/BrandedHomepage\.vue$/, to: '@/apps/secret/conceal/Homepage.vue' },
  { from: /^@\/views\/DisabledHomepage\.vue$/, to: '@/apps/secret/conceal/AccessDenied.vue' },
  { from: /^@\/views\/DisabledUI\.vue$/, to: '@/apps/secret/conceal/DisabledUI.vue' },
  { from: /^@\/views\/Feedback\.vue$/, to: '@/apps/secret/support/Feedback.vue' },
  { from: /^@\/views\/NotFound\.vue$/, to: '@/shared/components/errors/ErrorNotFound.vue' },

  // Components → Apps or Shared
  { from: /^@\/components\/secrets\/branded\//, to: '@/apps/secret/components/' },
  { from: /^@\/components\/secrets\/canonical\//, to: '@/apps/secret/components/' },
  { from: /^@\/components\/secrets\//, to: '@/apps/secret/components/' },
  { from: /^@\/components\/incoming\//, to: '@/apps/secret/components/incoming/' },
  { from: /^@\/components\/dashboard\//, to: '@/apps/workspace/components/dashboard/' },
  { from: /^@\/components\/account\//, to: '@/apps/workspace/components/account/' },
  { from: /^@\/components\/billing\//, to: '@/apps/workspace/components/billing/' },
  { from: /^@\/components\/teams\//, to: '@/apps/workspace/components/teams/' },
  { from: /^@\/components\/organizations\//, to: '@/apps/workspace/components/organizations/' },
  { from: /^@\/components\/colonel\//, to: '@/apps/kernel/components/' },
  { from: /^@\/components\/auth\//, to: '@/apps/session/components/' },

  // Flat components → categorized
  { from: /^@\/components\/(ConfirmDialog|SimpleModal)\.vue$/, to: '@/shared/components/modals/$1.vue' },
  { from: /^@\/components\/(BasicFormAlerts|PasswordStrengthChecker)\.vue$/, to: '@/shared/components/forms/$1.vue' },
  { from: /^@\/components\/(Domain.*|VerifyDomainDetails|CustomDomainPreview)\.vue$/, to: '@/apps/workspace/components/domains/$1.vue' },
  { from: /^@\/components\/(Feedback.*)\.vue$/, to: '@/apps/secret/components/support/$1.vue' },
  { from: /^@\/components\/(Homepage.*|DisabledHomepageTaglines)\.vue$/, to: '@/apps/secret/components/conceal/$1.vue' },

  // Remaining flat components → shared/ui
  { from: /^@\/components\/([A-Z][^/]+)\.vue$/, to: '@/shared/components/ui/$1.vue' },

  // Icons sprites (special case - stays in components)
  { from: /^@\/components\/icons\/sprites/, to: '@/shared/components/icons/sprites' },

  // Component directories → shared
  { from: /^@\/components\/base\//, to: '@/shared/components/base/' },
  { from: /^@\/components\/ui\//, to: '@/shared/components/ui/' },
  { from: /^@\/components\/common\//, to: '@/shared/components/common/' },
  { from: /^@\/components\/icons\//, to: '@/shared/components/icons/' },
  { from: /^@\/components\/logos\//, to: '@/shared/components/logos/' },
  { from: /^@\/components\/layout\//, to: '@/shared/components/layout/' },
  { from: /^@\/components\/navigation\//, to: '@/shared/components/navigation/' },
  { from: /^@\/components\/modals\//, to: '@/shared/components/modals/' },
  { from: /^@\/components\/ctas\//, to: '@/shared/components/ctas/' },
  { from: /^@\/components\/closet\//, to: '@/shared/components/closet/' },

  // Layouts
  { from: /^@\/layouts\/DefaultLayout\.vue$/, to: '@/shared/layouts/TransactionalLayout.vue' },
  { from: /^@\/layouts\/ImprovedLayout\.vue$/, to: '@/shared/layouts/ManagementLayout.vue' },
  { from: /^@\/layouts\/ColonelLayout\.vue$/, to: '@/shared/layouts/AdminLayout.vue' },
  { from: /^@\/layouts\/QuietLayout\.vue$/, to: '@/shared/layouts/MinimalLayout.vue' },
  { from: /^@\/layouts\//, to: '@/shared/layouts/' },
];

/**
 * Rewrite import paths in a source file using AST manipulation.
 */
export function rewriteImports(
  sourceFile: SourceFile,
  mappings: PathMapping[]
): { modified: boolean; count: number } {
  let count = 0;

  // Handle static imports
  for (const importDecl of sourceFile.getImportDeclarations()) {
    const moduleSpecifier = importDecl.getModuleSpecifierValue();
    const newPath = rewritePath(moduleSpecifier, mappings);

    if (newPath !== moduleSpecifier) {
      importDecl.setModuleSpecifier(newPath);
      count++;
    }
  }

  // Handle export from
  for (const exportDecl of sourceFile.getExportDeclarations()) {
    const moduleSpecifier = exportDecl.getModuleSpecifierValue();
    if (moduleSpecifier) {
      const newPath = rewritePath(moduleSpecifier, mappings);
      if (newPath !== moduleSpecifier) {
        exportDecl.setModuleSpecifier(newPath);
        count++;
      }
    }
  }

  // Handle dynamic imports: import('@/...')
  sourceFile.forEachDescendant((node) => {
    if (node.getKind() === SyntaxKind.CallExpression) {
      const callExpr = node.asKind(SyntaxKind.CallExpression);
      if (!callExpr) return;

      const expr = callExpr.getExpression();
      if (expr.getKind() === SyntaxKind.ImportKeyword) {
        const args = callExpr.getArguments();
        if (args.length > 0) {
          const arg = args[0];
          if (arg.getKind() === SyntaxKind.StringLiteral) {
            const stringLit = arg.asKind(SyntaxKind.StringLiteral);
            if (stringLit) {
              const value = stringLit.getLiteralValue();
              const newPath = rewritePath(value, mappings);
              if (newPath !== value) {
                stringLit.setLiteralValue(newPath);
                count++;
              }
            }
          }
        }
      }
    }
  });

  return { modified: count > 0, count };
}

/**
 * Apply path mappings to transform an import path.
 */
function rewritePath(importPath: string, mappings: PathMapping[]): string {
  for (const mapping of mappings) {
    if (mapping.from.test(importPath)) {
      return importPath.replace(mapping.from, mapping.to);
    }
  }
  return importPath;
}

/**
 * Handle Vue SFC files by extracting and rewriting the script section.
 * Note: ts-morph doesn't natively handle .vue files, so we need to
 * process them as text and extract the script content.
 */
export function extractVueScriptContent(vueContent: string): {
  before: string;
  script: string;
  after: string;
  lang: 'ts' | 'js';
} | null {
  // Match <script setup lang="ts"> or <script lang="ts"> or <script>
  const scriptMatch = vueContent.match(
    /(<script[^>]*>)([\s\S]*?)(<\/script>)/
  );

  if (!scriptMatch) {
    return null;
  }

  const [fullMatch, openTag, scriptContent, closeTag] = scriptMatch;
  const beforeScript = vueContent.slice(0, scriptMatch.index);
  const afterScript = vueContent.slice(
    (scriptMatch.index || 0) + fullMatch.length
  );

  const isTypeScript = openTag.includes('lang="ts"') || openTag.includes("lang='ts'");

  return {
    before: beforeScript + openTag,
    script: scriptContent,
    after: closeTag + afterScript,
    lang: isTypeScript ? 'ts' : 'js',
  };
}
