// src/plugins/core/configureZod.ts

import { z } from 'zod';

/**
 * Put Zod into "jitless" mode before any schema is constructed.
 *
 * Zod v4's object parser has a JIT fast path that builds a specialized validator
 * with `new Function(...)`. To decide whether it may, Zod runs a one-time
 * capability probe (`new Function("")`) the first time an object schema is
 * constructed. Under our Content-Security-Policy (script-src without
 * 'unsafe-eval') that probe throws; Zod catches it and transparently falls back
 * to its standard parser, so nothing breaks — but the probe still trips one
 * `script-src` violation per page load, which pollutes CSP violation reports.
 *
 * `jitless: true` makes Zod skip the fast path entirely. The probe is gated
 * behind `!jitless && allowsEval.value` (short-circuited), so it is never
 * evaluated: `new Function` is never called and no violation is emitted. This is
 * a no-op for correctness — under CSP Zod already used this path — at a
 * negligible validation-speed cost.
 *
 * Imported first in main.ts so the config is set before the app's object schemas
 * (defined at module load) are constructed.
 */
z.config({ jitless: true });
