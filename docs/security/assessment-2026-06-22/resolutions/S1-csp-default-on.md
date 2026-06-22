# S1 — Content-Security-Policy disabled by default

- **Severity:** High
- **Status:** Proposed fix
- **Affects default config?** **Yes**
- **Related:** S2 (other security headers), P1. Findings 05, 04 #1.
- **Primary files:** `etc/defaults/config.defaults.yaml:351-353` (`CSP_ENABLED` default false),
  `apps/api/v1/controllers/helpers.rb:171-208` (policy construction), `lib/onetime/middleware/security.rb`

## Problem (recap)

CSP is only emitted when `CSP_ENABLED=true`, which defaults to **false**. Confirmed live: `GET
/api/v2/status` returns **no `Content-Security-Policy`** header (`../evidence/headers_output.txt`). For a
product whose job is to display secrets, the default install ships without the single strongest
anti-XSS / data-exfiltration control.

The good news: the policy that *would* be emitted is already strong — nonce-based `script-src`, no
`unsafe-inline`/`unsafe-eval` for scripts, `default-src 'none'`, `frame-ancestors 'none'`
(`helpers.rb:176-208`). The fix is to turn it on, not to write it.

## Root cause

Secure-by-default was deferred to opt-in, presumably to avoid breaking custom deployments. The cost is
that every default deployment is unprotected.

## Prescribed resolution

1. **Flip the default to enabled.** `CSP_ENABLED` defaults `true`; keep the env override so operators
   with unusual embedding needs can disable it deliberately.
2. **Verify the nonce path end-to-end** with the SPA build: the server-rendered bootstrap must emit the
   per-response nonce on every `<script>` (including the rhales bootstrap and the Vite-built entry), and
   the SPA must not rely on inline event handlers/`unsafe-inline`. Add an automated check that the
   rendered HTML carries the nonce and no inline script slips through.
3. **Stage with Report-Only first.** Ship `Content-Security-Policy-Report-Only` (with a report sink) for
   one release to catch violations in real deployments, then promote to enforcing. This de-risks the
   default flip without leaving anyone exposed for long.
4. Reconcile with the DNS-widget inline-script item (finding S5, `useDnsWidget.ts:155-163`) and the
   `v-html` broadcast (S4) so neither violates the enforced policy (nonce the widget script; both are
   same-origin/sanitized already).

## Alternatives considered

- **Leave opt-in, document loudly:** rejected — documentation is not a control; the threat model
  (rendering secrets) demands secure-by-default.
- **Hash-based instead of nonce-based:** the nonce approach already exists and works with per-response
  rendering; no need to change strategy.

## Test / verification

- Default boot (no `CSP_ENABLED`) → response carries the strong CSP; `evidence/headers_output.txt`
  re-run shows it present.
- SPA smoke test (Playwright) loads/reveals a secret with CSP enforcing and **zero** console CSP
  violations.
- Report-Only telemetry shows no legitimate violations before promoting to enforce.

## Effort & risk

- **Effort:** Small to flip; Medium to verify the nonce/inline-script cleanliness across the SPA and
  rhales templates.
- **Risk:** Medium if flipped blind — hence the Report-Only staging. Once verified, low.
