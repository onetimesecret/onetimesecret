// src/tests/plugins/core/configureZod.spec.ts
//
// Guards the CSP-critical invariant that Zod runs in "jitless" mode.
//
// Zod v4's object parser has a JIT fast path built with `new Function(...)`,
// and probes for it with `new Function("")` the first time an object schema is
// constructed. Under our Content-Security-Policy (script-src without
// 'unsafe-eval') that probe trips a `script-src` violation. configureZod sets
// `jitless: true` so the probe is short-circuited and never runs. A regression
// here is invisible in the browser (Zod silently falls back) but pollutes CSP
// violation reports, so lock the behavior with a test.
//
// Run:
//   pnpm test src/tests/plugins/core/configureZod.spec.ts

import { describe, it, expect } from 'vitest';
import { z } from 'zod';

describe('configureZod', () => {
  it('puts Zod in jitless mode (no `new Function` eval probe)', async () => {
    await import('@/plugins/core/configureZod');
    // z.config() with no argument returns the live global config.
    expect(z.config().jitless).toBe(true);
  });
});
