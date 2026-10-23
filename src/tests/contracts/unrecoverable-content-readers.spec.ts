// src/tests/contracts/unrecoverable-content-readers.spec.ts
//
// A view that puts a one-time value on screen must mark the page as showing
// unrecoverable content (src/utils/unrecoverableContent.ts): otherwise an
// automatic reload (a lazy chunk that failed to load, an ended session)
// destroys the only copy. The mark is opt-in per view, so this test keeps the
// list of code that handles such a value explicit, keyed on how each value
// appears in frontend code: the `secret_value` field of a revealed secret or a
// receipt, and the `recoveryCodes` ref of the MFA composable. A new reader
// fails here until it either calls useUnrecoverableContent() itself, or
// renders inside a view that does, or keeps the value without rendering it,
// and is listed below with that reason.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const ROOT = resolve(process.cwd());
const SKIP = [/^src\/tests\//, /^src\/schemas\//, /^src\/types\//];
/** How a one-time value appears in frontend code. i18n keys are snake_case and do not match. */
const ONE_TIME_VALUE = /\bsecret_value\b|\brecoveryCodes\b/;

interface Reader {
  /** The file calls useUnrecoverableContent() itself. */
  marks: boolean;
  /** How the value is kept off an automatic reload. */
  why: string;
  /** For a component that does not mark: the view every importer must render inside. */
  renderedInside?: string;
}

/** Every source file that handles a one-time value. */
const READERS: Record<string, Reader> = {
  'src/shared/components/base/BaseShowSecret.vue': {
    marks: true,
    why: 'marks from the reveal request going out until record.secret_value is gone',
  },
  'src/apps/secret/reveal/ShowReceipt.vue': {
    marks: true,
    why: 'marks during the receipt fetch and while details.secret_value is shown',
  },
  'src/apps/secret/components/canonical/SecretDisplayCase.vue': {
    marks: false,
    why: "rendered only in BaseShowSecret's #reveal slot",
    renderedInside: 'BaseShowSecret',
  },
  'src/apps/secret/components/branded/SecretDisplayCase.vue': {
    marks: false,
    why: "rendered only in BaseShowSecret's #reveal slot",
    renderedInside: 'BaseShowSecret',
  },
  'src/apps/secret/composables/useSecretLifecycle.ts': {
    marks: false,
    why: 'keeps the value in state and renders nothing',
  },
  'src/apps/workspace/account/RecoveryCodes.vue': {
    marks: true,
    why: 'marks from the regenerate request going out until the codes panel is closed',
  },
  'src/apps/session/components/OtpSetupWizard.vue': {
    marks: true,
    why: 'marks from the enable request going out until the wizard closes',
  },
  'src/shared/composables/useMfa.ts': {
    marks: false,
    why: 'keeps the codes in state and renders nothing; exposes revealingRecoveryCodes for the views',
  },
};

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) return sourceFiles(full);
    return /\.(ts|vue)$/.test(name) ? [full] : [];
  });
}

const files = sourceFiles(join(ROOT, 'src'))
  .map((full) => relative(ROOT, full))
  .filter((rel) => !SKIP.some((re) => re.test(rel)));

const read = (rel: string) => readFileSync(join(ROOT, rel), 'utf8');

/** Files that import `rel` by its `@/` alias path. */
function importersOf(rel: string): string[] {
  const alias = rel.replace(/^src\//, '@/');
  return files.filter((f) => f !== rel && read(f).includes(alias));
}

describe('readers of one-time values are accounted for (unrecoverable content)', () => {
  it('every file that handles a one-time value is listed with how it stays off an automatic reload', () => {
    const readers = files.filter((rel) => ONE_TIME_VALUE.test(read(rel))).sort();
    // A new entry here needs useUnrecoverableContent() in that view, or a
    // reason in READERS why the value is never on screen without it.
    expect(readers).toEqual(Object.keys(READERS).sort());
  });

  const marking = Object.entries(READERS).filter(([, r]) => r.marks);
  it.each(marking.map(([rel]) => [rel]))('%s calls useUnrecoverableContent', (rel) => {
    expect(read(rel)).toContain('useUnrecoverableContent(');
  });

  const nested = Object.entries(READERS).filter(([, r]) => r.renderedInside);
  it.each(nested.map(([rel, r]) => [rel, r.renderedInside as string]))(
    '%s is imported only by views that render inside %s',
    (rel, container) => {
      const importers = importersOf(rel);
      expect(importers.length).toBeGreaterThan(0);
      for (const importer of importers) {
        expect(read(importer), `${importer} renders ${rel} outside ${container}`).toContain(
          container
        );
      }
    }
  );
});
