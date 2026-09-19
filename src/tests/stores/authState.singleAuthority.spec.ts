// src/tests/stores/authState.singleAuthority.spec.ts
//
// Properties of the SOURCE TREE that #4458 and #4459 require to stay true.
// They cannot be asserted through behaviour: "no code path reads X" and
// "no other caller fetches Y" are statements about every file, including
// ones no test mounts. So this scans the sources.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

const SRC = join(process.cwd(), 'src');

function sourceFiles(dir: string = SRC): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      // Tests may mention anything; they are not code paths.
      return relative(SRC, path) === 'tests' ? [] : sourceFiles(path);
    }
    return /\.(ts|vue)$/.test(name) ? [path] : [];
  });
}

const files = sourceFiles().map((path) => ({
  path: relative(process.cwd(), path),
  text: readFileSync(path, 'utf8'),
}));

/** Drops comments so that prose about a thing is not mistaken for use of it. */
function code(text: string): string {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/(^|[^:'"`])\/\/.*$/gm, '$1');
}

const matching = (pattern: RegExp) =>
  files.filter((file) => pattern.test(code(file.text))).map((file) => file.path);

describe('single authentication authority (#4458)', () => {
  it('scans a real tree', () => {
    expect(files.length).toBeGreaterThan(200);
    expect(files.some((f) => f.path === 'src/shared/stores/authStore.ts')).toBe(true);
  });

  it('no code path reads or writes ots_auth_state', () => {
    expect(matching(/ots_auth_state/)).toEqual([]);
  });

  it('had_valid_session is mentioned by the schema only: nothing decides from it', () => {
    expect(matching(/had_valid_session|hadValidSession/i)).toEqual(['src/schemas/contracts/bootstrap.ts']);
  });

  it('the client status is assigned in bootstrapStore only', () => {
    expect(matching(/\bauthStatus\s*=(?!=)/)).toEqual(['src/shared/stores/bootstrapStore.ts']);
  });

  it('authStore keeps no writable authentication flag of its own', () => {
    const authStore = files.find((f) => f.path === 'src/shared/stores/authStore.ts');
    expect(authStore).toBeDefined();
    const text = code(authStore?.text ?? '');

    expect(text).not.toMatch(/isAuthenticated\.value\s*=(?!=)/);
    expect(text).not.toMatch(/const isAuthenticated = ref/);
    expect(text).not.toMatch(/sessionStorage\.(getItem|setItem)/);
  });

  it('no local patch states who is signed in', () => {
    // update() drops these keys anyway; a caller passing them is a bug in waiting.
    expect(matching(/\.update\(\s*\{[^}]*\b(authenticated|awaiting_mfa|auth_status)\s*:/)).toEqual([]);
  });
});

describe('one refresh coordinator (#4459)', () => {
  it('GET /bootstrap/me is requested from exactly one place', () => {
    expect(matching(/['"`]\/bootstrap\/me['"`]/)).toEqual(['src/shared/stores/authStore.ts']);
  });

  it('bootstrapStore no longer fetches', () => {
    const store = files.find((f) => f.path === 'src/shared/stores/bootstrapStore.ts');
    expect(code(store?.text ?? '')).not.toMatch(/\bfetch\(|\brefresh\s*\(/);
  });

  it('nothing calls the removed bootstrapStore.refresh()', () => {
    expect(matching(/bootstrapStore\.refresh\(/)).toEqual([]);
  });

  it('MastHead makes no startup request (#4456)', () => {
    const mastHead = files.find((f) => f.path === 'src/shared/components/layout/MastHead.vue');
    expect(code(mastHead?.text ?? '')).not.toMatch(/onMounted|\.refresh\(/);
  });
});

describe('no API error handler writes authentication state (#4460)', () => {
  it('the three writers of the client status are called from the two auth stores only', () => {
    expect(matching(/\.(withholdAuthority|applySnapshot|resetForLogout)\(/).sort()).toEqual([
      'src/shared/stores/authStore.ts',
      'src/shared/stores/bootstrapStore.ts',
    ]);
  });

  it('a local sign-out is never called from a catch block', () => {
    // A rejection REQUESTS reconciliation (authStore.noteApiRejection); it does
    // not sign the client out. The sign-out callers that exist are success
    // paths and the /logout route.
    const inCatch = /catch\s*(\([^)]*\))?\s*\{[^}]*\b(logout|logoutMinimal|setAuthenticated)\(/;
    expect(matching(inCatch)).toEqual([]);
  });

  it('the axios interceptors reach the auth store through noteApiRejection only', () => {
    const interceptors = files.find((f) => f.path === 'src/plugins/axios/interceptors.ts');
    const uses = code(interceptors?.text ?? '').match(/useAuthStore\(\)\.(\w+)/g) ?? [];

    expect(uses).toEqual(['useAuthStore().noteApiRejection']);
  });

  it('admin-expiry recovery stays on the admin surface', () => {
    expect(
      matching(/noteAdminSessionExpiry|adminSessionExpired\b/).filter(
        (path) => !path.startsWith('src/apps/admin/')
      )
    ).toEqual([]);
  });

  it('the old client-only logout at MAX_FAILURES is gone', () => {
    const authStore = files.find((f) => f.path === 'src/shared/stores/authStore.ts');
    const text = code(authStore?.text ?? '');
    const noteFailure = text.slice(text.indexOf('function noteFailure'), text.indexOf('function noteApiRejection'));

    expect(noteFailure).toContain('MAX_FAILURES');
    expect(noteFailure).not.toMatch(/logout|resetForLogout|\$reset/);
  });
});
