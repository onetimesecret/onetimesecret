// vitest.smoke.config.ts

// The vitest part of the smoke test (`pnpm test:smoke:vitest`). It reuses
// vitest.config.ts unchanged and narrows each project's include to the
// curated list in src/tests/smoke-files.ts. globalSetup, setupFiles, the
// console guard, aliases, excludes and the pool all carry over.
//
// A stale list fails here, before any test runs ("failed to load config"),
// rather than quietly running fewer files.
//
// Default export only: a named export next to it makes rolldown warn
// (MIXED_EXPORTS) when vitest bundles the config.

import { findSmokeListProblems, SMOKE_FILES, type SmokeProject } from './src/tests/smoke-files';
import base from './vitest.config';

const ROOT = import.meta.dirname;

const projects = (base.test?.projects ?? []) as unknown as SmokeProject[];

for (const name of Object.keys(SMOKE_FILES)) {
  if (!projects.some((p) => p.test.name === name)) {
    throw new Error(`[smoke] vitest.config.ts has no '${name}' project`);
  }
}

const problems = findSmokeListProblems(ROOT, projects);
if (problems.length > 0) {
  throw new Error(
    `[smoke] src/tests/smoke-files.ts is out of date:\n  - ${problems.join('\n  - ')}`
  );
}

export default {
  ...base,
  test: {
    ...base.test,
    // A project with no entry in SMOKE_FILES is left out of the smoke run.
    projects: projects
      .filter((p) => p.test.name in SMOKE_FILES)
      .map((p) => ({
        ...p,
        test: { ...p.test, include: [...SMOKE_FILES[p.test.name as keyof typeof SMOKE_FILES]] },
      })),
  },
};
