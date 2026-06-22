# S5 — DNS-widget script injected without a CSP nonce

- **Severity:** Low — **NEEDS-VALIDATION** (confirm at runtime under enforced CSP, and confirm the widget is still in use)
- **Status:** Proposed fix (conditional on validation)
- **Affects default config?** **No** today (CSP ships off — S1). Becomes relevant once S1 lands and CSP is enforced.
- **Related:** S1 (strict nonce-based `script-src` is exactly what would block this). Finding 05 #6.
- **Primary files:**
  - `src/shared/composables/useDnsWidget.ts:155-163` (creates `<script>`, sets `script.src = dnsWidgetJs`, appends to `<head>` with **no `nonce`**)
  - `src/shared/composables/useDnsWidget.ts:14` (vendored asset imported via Vite `?url`: `@/assets/approximated/dnswidget.v1.js`)
  - `src/apps/workspace/components/domains/DnsWidget.vue:120-122` (the only caller; mounts in the authenticated custom-domain admin flow)
  - Nonce plumbing: `src/schemas/contracts/bootstrap.ts:589` (`nonce` is in the schema) **but** `src/tests/contracts/bootstrap-schema-contract.spec.ts:44-45` documents it as **intentionally not passed to Vue app state**

## Confirm first

Two things must be verified before implementing, because they change whether any work is needed and which fix applies:

1. **Is the DNS widget still in use?** It is referenced only by `DnsWidget.vue`
   (`src/apps/workspace/components/domains/DnsWidget.vue`) in the custom-domain admin flow. If
   custom-domains/the widget have been retired, the fix is to **delete** `useDnsWidget.ts` and the
   vendored asset, not to nonce it. Confirm with the maintainers first.
2. **Does it actually break under the strict CSP?** Dynamically-created (non-parser-inserted)
   `<script>` elements are generally **allowed** under a nonce-based `script-src` even without a
   nonce — so this may keep working as-is once S1 is enforced. Validate at runtime with
   `CSP_ENABLED=true`: load the custom-domain page, trigger the widget, and check for a
   `Refused to load the script … because it violates … Content-Security-Policy` console error. If it
   loads cleanly, S5 is informational only (still worth the nonce for future-proofing — see below).

## Problem (recap)

`useDnsWidget.loadAssets()` (`useDnsWidget.ts:148-164`) dynamically creates a `<script>`, sets its
`src` to the Vite-resolved vendored URL, and appends it to `<head>` with no `nonce` attribute. Under
the strict CSP that S1 turns on (`script-src 'nonce-…'`, no `unsafe-inline`), a *parser-inserted*
script without a nonce would be blocked; a *programmatically inserted* one usually is not — hence
NEEDS-VALIDATION. If the policy later adopts `strict-dynamic`, behavior shifts again (then a nonce on
the inserting context matters more). Today, with CSP off by default, nothing breaks; this is a latent
issue scoped to the moment S1 ships.

The asset is **vendored same-origin** (not a remote CDN), so this is a functional-compatibility concern
under CSP, not a third-party-script trust concern. (Separately, the vendored widget uses `innerHTML`
heavily — `dnswidget.v1.js` — which is its own vendor-code surface to track, but out of scope for S5.)

## Root cause

The widget loader was written to inject its `<script>`/`<link>` imperatively at runtime and predates a
nonce-aware loading path. The per-response nonce, although present server-side and in the bootstrap
schema (`bootstrap.ts:589`), is **deliberately not exposed to the Vue app** (`bootstrap-schema-contract.spec.ts:44-45`),
so the composable has no nonce to attach even if it wanted to.

## Prescribed resolution

Make the injected script CSP-clean once S1 is enforced. Preference order:

### Implementation steps

1. **(Preferred) Load the widget as a bundled module instead of injecting a `<script>` tag.** The asset
   is already vendored and Vite-resolved (`useDnsWidget.ts:14`). If `dnswidget.v1.js` can be imported as
   an ES module (dynamic `import()` of the vendored file, or a static import that exposes
   `window.apxDns`), the script never goes through a runtime `<script>` injection and is covered by the
   single same-origin bundle that the nonce already authorizes. This removes the CSP question entirely
   and is the most durable fix. Verify the vendored file's shape (it currently registers `window.apxDns`)
   to confirm it can be consumed as a module; it may need a tiny vendored wrapper.

2. **(If injection must stay) Attach the per-response nonce to the created `<script>` (and `<link>`).**
   This requires exposing the nonce to the SPA, which today is intentionally withheld:
   - Add a narrowly-scoped accessor for the nonce. Cleanest: read it from the server-rendered DOM at
     runtime rather than from Pinia — e.g. reuse the nonce already present on a server-emitted script
     tag (rhales sets `config.nonce_header_name = 'onetime.nonce'` and stamps hydration script tags),
     or expose it via a dedicated `<meta name="csp-nonce" content="…">` carrying the per-response value.
     `document.querySelector('script[nonce]')?.nonce` (the IDL `.nonce` reflection, which is readable
     in-script even though the attribute is hidden from DOM serialization) is a common pattern:
     ```ts
     const nonce = document.querySelector<HTMLScriptElement>('script[nonce]')?.nonce;
     const script = document.createElement('script');
     script.src = dnsWidgetJs;
     if (nonce) script.setAttribute('nonce', nonce);
     // same for the <link rel="stylesheet"> if style-src is tightened later
     ```
   - If instead the nonce is exposed through bootstrap, do it as a deliberate, documented change and
     update `bootstrap-schema-contract.spec.ts:44-45` (which currently asserts the opposite). Note that
     a nonce read from the *initial* page-load bootstrap is the *page-load* nonce; for an SPA that
     stays on one document this is fine (the document's nonce does not rotate per client navigation),
     but document this assumption.

3. **(Lowest preference) Rely on dynamic-insertion being allowed.** If validation (Confirm First #2)
   shows the injected script loads fine under the enforced CSP, you may leave it — but add a comment at
   `useDnsWidget.ts:155-163` recording that this depends on the policy **not** using `strict-dynamic`
   and on dynamic scripts being exempt, so a future CSP tightening re-opens S5.

4. **Reconcile with S1.** S1's checklist already calls out nonce-ing this widget. Whichever path is
   chosen, include the custom-domain page in S1's Report-Only telemetry review so any `script-src`
   violation from the widget is caught before CSP is promoted to enforcing.

### Alternatives considered

- **Add `'unsafe-inline'`/widen `script-src` to accommodate the widget:** rejected — it would gut the
  whole point of S1's nonce-only policy for the entire app to satisfy one admin-only widget.
- **`strict-dynamic`:** would let a nonce'd loader transitively authorize the widget, but it changes the
  policy semantics app-wide and still requires the *loader* to carry a nonce; more blast radius than
  bundling the module.
- **Do nothing:** acceptable only if validation proves it loads under enforced CSP **and** the team
  accepts the `strict-dynamic` caveat — but bundling/nonce-ing is cheap insurance.

## Test / verification

- **Runtime (the key check):** with `CSP_ENABLED=true`, open the custom-domain admin page that mounts
  `DnsWidget.vue`, trigger `initWidget()`, and confirm the widget script and CSS load with **zero** CSP
  violations in the console. Re-run after the fix to confirm the nonce/bundled path works.
- **Unit (if nonce path chosen):** mock a nonce source in the DOM and assert
  `loadAssets()` sets the `nonce` attribute on the created `<script>` (and `<link>`).
- **Regression:** confirm the widget still initializes and DNS-record verification events
  (`apx-dnswidget-records-completely-verified`, etc., `useDnsWidget.ts:170-188`) still fire after the
  change.
- **Removal path:** if the widget is confirmed retired, grep that nothing else imports
  `useDnsWidget`/`dnswidget.v1.js` before deleting, and confirm the custom-domain UI no longer
  references `#apxdnswidget` (`DnsWidget.vue:164`).

## Effort & risk

- **Effort:** Small-to-Medium. Nonce-attach is small but needs a sanctioned nonce-exposure decision
  (touches the bootstrap contract test). Converting to a bundled module is Medium (depends on the
  vendored file's module shape). Removal (if retired) is small.
- **Risk:** Low. Pure additive hardening gated behind runtime validation; no behavior change unless CSP
  is enforced. Main hazard is exposing the nonce more broadly than intended — mitigate by reading it
  from the existing server-rendered DOM rather than threading it through app state, and by keeping the
  accessor narrow and documented.
