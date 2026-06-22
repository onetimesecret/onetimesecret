# S4 — `v-html` in GlobalBroadcast (DOMPurify-mitigated)

- **Severity:** Low
- **Status:** Proposed hardening (defense-in-depth; no active vulnerability)
- **Affects default config?** **No**
- **Related:** S1 (the broadcast must render cleanly under the enforced CSP). Finding 05 #5.
- **Primary files:**
  - `src/shared/components/ui/GlobalBroadcast.vue:139` (`<span v-html="sanitizedContent"></span>`)
  - `src/shared/components/ui/GlobalBroadcast.vue:43-47` (`decodeHTMLEntities`)
  - `src/shared/components/ui/GlobalBroadcast.vue:50-57` (DOMPurify config, `ALLOWED_TAGS: ['a']`)
  - Content source: `src/shared/layouts/BaseLayout.vue` → `:content="global_banner ?? null"`,
    read from `bootstrapStore` (`global_banner`, `bootstrap.ts:580`)

## Problem (recap)

The single application-code `v-html` (`GlobalBroadcast.vue:139`) renders the operator-set global
broadcast banner. Input flows: `global_banner` (server bootstrap, admin/operator-set in Redis) →
`decodeHTMLEntities()` (`:43-47`, writes to a detached `<textarea>.innerHTML`, reads `.value`) →
`DOMPurify.sanitize()` with `ALLOWED_TAGS: ['a']`, `ALLOWED_ATTR: ['href','target','rel','class']`
(`:50-57`) → bound via `v-html`.

This is **not** a user-facing XSS today: the content is operator-controlled, the decode-then-sanitize
order is correct, and DOMPurify with an anchor-only allowlist strips `<script>`, event-handler
attributes, and (by default) `javascript:`/`data:` URIs. The risk is residual: a `v-html` sink whose
safety depends entirely on one library call and a tight config, with an operator-trust assumption.

## Root cause

The banner supports a small amount of rich text (a link), so it is rendered as HTML rather than text.
That choice introduces an HTML sink that must be kept narrow and must survive future refactors and CSP
enforcement.

## Prescribed resolution

Keep the sink only if the link feature is required; otherwise remove it. Either way, lock down the
allowlist and add tests that prove malicious payloads are stripped.

### Implementation steps

1. **Prefer no `v-html` where possible.** If the banner does not actually need an inline anchor,
   render `props.content` as plain text (`{{ content }}`, which Vue escapes) and delete the DOMPurify
   path entirely. This removes the sink and the dependency-trust assumption. Confirm with product
   whether banners ever contain links before choosing this path.

2. **If the anchor is required, keep the sink but harden it.** Retain the existing decode → sanitize →
   bind order (`:43-57`) and tighten the config:
   - Enforce safe URL schemes explicitly rather than relying on defaults:
     ```ts
     const sanitizeConfig = {
       ALLOWED_TAGS: ['a'],
       ALLOWED_ATTR: ['href', 'target', 'rel', 'class'],
       // Only http/https/mailto; blocks javascript:, data:, vbscript: explicitly.
       ALLOWED_URI_REGEXP: /^(?:https?|mailto):/i,
     };
     ```
   - Force safe link relations. DOMPurify does not add `rel` for you; use a post-sanitize hook (or a
     small DOM pass) to set `rel="noopener noreferrer nofollow"` and constrain `target` to `_blank`
     so an operator-set link can't reach `window.opener`:
     ```ts
     DOMPurify.addHook('afterSanitizeAttributes', (node) => {
       if (node.tagName === 'A' && node.getAttribute('href')) {
         node.setAttribute('rel', 'noopener noreferrer nofollow');
         if (node.getAttribute('target')) node.setAttribute('target', '_blank');
       }
     });
     ```
     Register the hook once at module scope (not per-render) and keep it scoped to this component's
     sanitize call.

3. **Reconsider `decodeHTMLEntities` (`:43-47`).** Writing operator content to a detached
   `<textarea>.innerHTML` is safe for a `<textarea>` (its content is treated as text, scripts do not
   execute), and the result is sanitized afterward. Keep it, but add a comment documenting *why* the
   order (decode → sanitize → bind) is safe so a future edit doesn't reorder it. If entity decoding is
   not actually needed for the banner, drop this step to shrink the surface.

4. **Ensure it renders under the enforced CSP (S1).** The strict CSP is `script-src 'nonce-…'` with no
   `unsafe-inline` for scripts; the broadcast injects **markup**, not scripts, so it is unaffected by
   `script-src`. Confirm the rendered anchor needs no inline style/handler. With S1's
   `style-src 'self' 'unsafe-inline'` the `class`-based styling is fine. Add this case to the S1
   Report-Only telemetry review so a live banner with a link is observed to produce zero CSP
   violations before promoting to enforce.

5. **Keep DOMPurify current.** Track the `dompurify` dependency (import at `GlobalBroadcast.vue:8`) for
   upstream security releases; a stale sanitizer is the main way this becomes a real bug.

### Alternatives considered

- **Leave as-is (accept the finding):** defensible given Low severity and operator-only input, but the
  marginal hardening (explicit URI allowlist + `rel`) is cheap and removes the implicit trust in
  DOMPurify defaults. Worth doing.
- **Trusted Types instead of DOMPurify:** S1 notes a commented-out `require-trusted-types-for 'script'`.
  Trusted Types governs *script* sinks, not `v-html` markup injection, so it does not directly cover
  this case; DOMPurify remains the right control here. (DOMPurify can produce a `TrustedHTML` if TT is
  later enforced — keep that in mind, but it is not required for S4.)
- **Markdown/link-only mini-renderer:** more code than the problem warrants for a single anchor.

## Test / verification

- **Unit (sanitization):** add a `GlobalBroadcast` spec that mounts the component with hostile
  `content` and asserts the rendered HTML is neutralized. Cover at minimum:
  - `<script>alert(1)</script>` → no `<script>` in output.
  - `<a href="javascript:alert(1)">x</a>` → `href` removed/neutralized (no `javascript:`).
  - `<img src=x onerror=alert(1)>` → element/handler stripped (`<img>` not in allowlist, `onerror`
    gone).
  - `<a href="https://evil.example" onclick="alert(1)">x</a>` → `onclick` stripped; `rel` set to
    `noopener noreferrer nofollow`.
  - Entity-encoded payload (e.g. `&lt;script&gt;…`) → decoded then sanitized, still inert (guards the
    decode→sanitize order at `:43-57`).
  Assert against `wrapper.find('span').html()` / `innerHTML`.
- **CSP smoke (ties to S1):** with `CSP_ENABLED=true`, render a banner containing a link and confirm
  **zero** console CSP violations (Playwright), and that the link carries `rel="noopener…"`.

## Effort & risk

- **Effort:** Small. Config tightening + one DOMPurify hook + a focused spec; or smaller still if the
  banner becomes plain text.
- **Risk:** Very low. The change only narrows what the sink accepts. The only regression to watch is an
  operator who relied on a non-http(s)/mailto scheme or a non-anchor tag in a banner — vanishingly rare
  and arguably desirable to block. Note the `ALLOWED_URI_REGEXP` change in release notes.
