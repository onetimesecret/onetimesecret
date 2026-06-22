# D2 — `form-data` 4.0.5 (via `axios`) CRLF injection (GHSA-hmw2-7cc7-3qxx)

- **Severity:** Medium (scanner-rated High; mitigated in this app — see below)
- **Status:** Proposed fix (dependency bump / override)
- **Affects default config?** Yes (ships in every browser bundle), but **not practically exploitable** — the vulnerable Node helper is unreachable from the browser adapter.
- **Related:** Finding 06 #2; lockfile-integrity §2. Same JS supply-chain surface as D7 (dev-only JS CVEs).
- **Primary files:** `pnpm-lock.yaml:3129` (`form-data@4.0.5`), `pnpm-lock.yaml:7027-7032`
  (`axios@1.16.0` → `form-data: 4.0.5`), `package.json:158` (`"axios": "^1.16.0"`),
  `pnpm-workspace.yaml` (`overrides:` block).

## Problem (recap)

`form-data` 4.0.5 is vulnerable to **GHSA-hmw2-7cc7-3qxx** (fixed in `>= 4.0.6`): an attacker who
controls multipart field names/filenames can inject CRLF sequences into the generated multipart body.
It is the **only production-tree** JS advisory reported by `pnpm audit --prod`, pulled transitively via
`axios`:

- `pnpm-lock.yaml:7027` — `axios@1.16.0` lists `form-data: 4.0.5` as a runtime dependency.
- `package.json:158` — `"axios": "^1.16.0"`.
- Audit paths: `.>axios>form-data` and `.>@vueuse/integrations>axios>form-data`
  (`@vueuse/integrations@14.3.0` declares `axios` as an *optional* dependency, `pnpm-lock.yaml:6874`).

## Root cause

A transitive dependency resolved one patch below the fix. `form-data` is `axios`'s **Node-runtime**
multipart helper. In this codebase `axios` is consumed only by the **browser** bundle
(`src/shared/composables/useApi.ts` and the shared stores); the browser build uses axios's
XHR/fetch adapter, which uses the native `FormData`/`Blob` APIs — **not** the Node `form-data`
package. So the vulnerable code path is not bundled into anything that executes at runtime, which is
why this is Medium-in-practice despite the High scanner rating. It still appears in the lockfile and
the prod dependency tree, so it must be cleared as defence-in-depth and to silence the prod-tree alert.

## Prescribed resolution

### Implementation steps

1. **Preferred — bump `axios`** so it naturally resolves `form-data >= 4.0.6`:
   ```bash
   pnpm update axios            # stays within the ^1.16.0 range; pulls latest 1.x
   ```
   If the latest 1.x still pins `form-data < 4.0.6`, widen/refresh the manifest:
   ```bash
   pnpm add axios@latest        # within major 1; updates package.json:158
   ```
   Then confirm the lockfile moved:
   ```bash
   grep -n "form-data@" pnpm-lock.yaml      # expect 4.0.6+ only
   ```

2. **Belt-and-suspenders — add a pnpm `overrides` entry** in `pnpm-workspace.yaml`
   (the `overrides:` block already exists with `brace-expansion`, `yaml`, etc.):
   ```yaml
   overrides:
     '@types/estree': '1.0.9'
     'brace-expansion': '1.1.13'
     'flatted': '^3.4.2'
     'yaml': '^2.8.3'
     'form-data': '>=4.0.6'   # GHSA-hmw2-7cc7-3qxx
   ```
   Then refresh:
   ```bash
   pnpm install --frozen-lockfile=false
   ```
   The override is the most robust choice because it pins **every** transitive path (both the direct
   `axios` path and the `@vueuse/integrations > axios` path) regardless of what axios's own range
   permits in future.

3. **Rebuild the frontend bundle** so the resolved tree is what actually ships:
   ```bash
   pnpm run build
   ```
   (The production OCI image runs `pnpm install --frozen-lockfile`, so the committed lockfile is what
   gets built — the lockfile change is the load-bearing artifact.)

### Alternatives considered

- **Do nothing (rely on the mitigation):** rejected. The mitigation (browser adapter doesn't use the
  Node helper) is real but fragile — a future code change that imports axios in a Node context (an SSR
  layer, a build script, a Node test that posts multipart) would silently reactivate the path. A patch
  bump is free and removes the latent risk.
- **Drop axios for native `fetch`:** larger refactor of `useApi.ts` and the stores; out of scope for a
  CVE remediation and unnecessary given the override fixes it in one line.

## Test / verification

```bash
# 1. No vulnerable form-data remains in the production tree
pnpm audit --prod
#    -> expect "No known vulnerabilities found" (or no GHSA-hmw2-7cc7-3qxx)

# 2. Confirm the resolved version
pnpm why form-data
#    -> every path resolves to >= 4.0.6

# 3. Frontend test suite still green (axios-backed API calls)
pnpm run test
```

## Effort & risk

- **Effort:** Trivial — one `overrides` line (or `pnpm update axios`) + lockfile refresh + bundle rebuild.
- **Risk:** Very low. `form-data` 4.0.6 is a patch release; axios's public API is unchanged. Covered by
  the existing frontend test suite and the `axios-mock-adapter` tests (`pnpm-lock.yaml:7021`).
