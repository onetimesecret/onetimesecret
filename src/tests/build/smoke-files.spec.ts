// src/tests/build/smoke-files.spec.ts

/**
 * The smoke test's vitest list (src/tests/smoke-files.ts) must match the
 * files on disk and the projects in vitest.config.ts. The smoke job runs
 * only on develop, so without this check a PR that renames, deletes or
 * moves a listed file would pass and break the smoke job after merge.
 * This file runs in the node project, so T2 checks the list on every PR.
 *
 * Run:
 *   pnpm test src/tests/build/smoke-files.spec.ts
 */

import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { findSmokeListProblems, SMOKE_FILES, type SmokeProject } from '../smoke-files';

const ROOT = resolve(import.meta.dirname, '../../..');

// Loaded through a variable on purpose. A static import makes
// `pnpm type-check:tests` type-check vitest.config.ts and everything it
// pulls in (vite, @vitejs/plugin-vue): about 500 more files and 1.2 GB more
// memory, which overruns Node's default heap. At runtime it is the same
// module either way.
const VITEST_CONFIG = '../../../vitest.config';
const { default: base } = (await import(/* @vite-ignore */ VITEST_CONFIG)) as {
  default: { test?: { projects?: unknown[] } };
};
const projects = (base.test?.projects ?? []) as SmokeProject[];

describe('smoke vitest list', () => {
  it('matches the files on disk and the vitest projects', () => {
    expect(findSmokeListProblems(ROOT, projects)).toEqual([]);
  });

  it('reports a missing file, a duplicate and a file in the wrong project', () => {
    const problems = findSmokeListProblems(ROOT, projects, {
      dom: [
        'src/tests/no-such-file.spec.ts',
        SMOKE_FILES.dom[0],
        SMOKE_FILES.dom[0],
        SMOKE_FILES.node[0],
      ],
      node: [SMOKE_FILES.node[1]],
    });
    expect(problems).toEqual([
      'missing on disk (renamed or deleted?): src/tests/no-such-file.spec.ts',
      `listed twice: ${SMOKE_FILES.dom[0]}`,
      `the 'dom' project would not run it: ${SMOKE_FILES.node[0]}`,
      `listed under 'dom' but runs in 'node': ${SMOKE_FILES.node[0]}`,
    ]);
  });

  it('reports a file under src/tests/e2e and an empty list', () => {
    const problems = findSmokeListProblems(ROOT, projects, {
      dom: ['src/tests/e2e/example.spec.ts'],
      node: [],
    });
    expect(problems).toEqual([
      'missing on disk (renamed or deleted?): src/tests/e2e/example.spec.ts',
      "the 'dom' project would not run it: src/tests/e2e/example.spec.ts",
      "the 'node' list is empty",
    ]);
  });

  it('reports a project missing from the config', () => {
    const domOnly = projects.filter((p) => p.test.name === 'dom');
    expect(findSmokeListProblems(ROOT, domOnly)).toEqual(["no 'node' project in vitest.config.ts"]);
  });
});
