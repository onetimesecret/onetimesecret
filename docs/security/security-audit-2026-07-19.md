# Security & Code Audit — 2026-07-19

- **Repo:** `/Users/d/Projects/dev/onetimesecret/onetimesecret`
- **Method:** `/audit` workflow (fan-out finders per dimension → adversarial refute panel per candidate → synthesis), plus manual empirical verification of the contested HIGH findings.
- **Workflow run:** `wf_e45a0e8f-571` (first pass session-limited: 12/31 agents failed; resumed to completion: 76 agents, 0 errors, deps dimension replayed from cache).
- **Dimensions:** security, correctness, tests, dead code, deps.

Note on provenance: the workflow's own synthesis reported "3 high (session fixation via URL-param SID, two untested MFA security controls)". That headline is not reliable — the synthesis over-trusted a split verification panel. The findings below reflect manual verification of the decisive cases against the actual code.

---

## Bottom line: zero real vulnerabilities

The workflow reported "3 high" findings. None survive scrutiny. The three HIGH "session" findings are false positives (verified empirically). The two MFA-labeled HIGH findings are real test-coverage gaps, not live bugs.

---

## The three HIGH "session" findings are false positives

Findings as filed:
- `weak-crypto` — `session.rb:63` — Session IDs generated with non-cryptographic `Kernel.rand` (Mersenne Twister) instead of a CSPRNG.
- `session-handling` — `middleware_stack.rb:332` — Session cookie set without the HttpOnly attribute.
- `session-handling` — `middleware_stack.rb:333` — Session ID accepted from a URL query parameter (cookie_only disabled), enabling session fixation and SID leakage.

All three rested on one claim: that `Onetime::Session` shadows Rack's `DEFAULT_OPTIONS` and drops the security options. It doesn't. The `unless defined?(DEFAULT_OPTIONS)` guard at `session.rb:62` resolves the constant through the ancestor chain to `Rack::Session::Abstract::Persisted::DEFAULT_OPTIONS`, so the block never executes.

Confirmed empirically under the app's own `rack-session 2.1.2`:

```
guard defined?(DEFAULT_OPTIONS) => "constant"   # block skipped
child defined its own const?    => false
resolved has cookie_only? true (val=true)
resolved has httponly?    true (val=true)
resolved has secure_random? true (val=SecureRandom)
```

The mount at `middleware_stack.rb:332` passes only `secret/expire_after/key/secure/same_site` — it never overrides `cookie_only`, `httponly`, or `secure_random`. So session IDs use `SecureRandom`, cookies are HttpOnly, and `cookie_only:true` blocks the URL-param fixation path. Five of the six verifiers got this right; the one that "confirmed" fixation had its premise backwards. Do not action these.

Latent nit, not a finding: the dead guard block means the child's intended `sidbits: 256` also never applies, so SIDs fall back to the parent's entropy default. Still CSPRNG, still unguessable — cosmetic vs. the documented 64-char format.

---

## What's actually worth the time

### Two real test-coverage gaps on MFA enforcement (finder labeled HIGH; they are gaps, not live bugs)

- `apps/web/auth/operations/mfa_state_checker.rb:138` — `query_mfa_state` is the DB read that arms MFA enforcement (feeds `DetectMfaRequirement` via the after-login hook) and has **zero tests**; the consumer specs pass hard-coded booleans, so the real table/count logic never runs. A silent-false regression would disable MFA enforcement with nothing to catch it.
- `apps/web/auth/operations/prepare_mfa_session.rb:89` — writes the `awaiting_mfa` guard flag; no direct test exercises it. (The "complete MFA bypass" framing was overstated — there is defense-in-depth — but the coverage hole is real.)

### One latent correctness bug

- `lib/onetime/middleware/identity_resolution.rb:104` reads `session['account_external_id']`, a key nothing ever writes (full-mode writes `external_id`), so full-mode identity always resolves to `no_identity`. Currently inert because nothing consumes `env['identity.*']` — but it is a landmine for whoever wires a consumer expecting it to work.

### Confirmed dead code (cleanup only, all verified genuinely uncalled)

- `lib/onetime/application/authorization_policies.rb:152` — `verify_all_roles!`
- `lib/onetime/models/custom_domain.rb:304` — `owned_by_organization?`
- `lib/onetime/models/custom_domain.rb:412` — `check_identifier!`
- `lib/onetime/models/organization.rb:269` — `get_customer` (deprecated alias)
- `lib/onetime/models/organization.rb:307` — `unarchive!`
- `lib/onetime/models/secret.rb:97` and `lib/onetime/models/receipt.rb:197` — `older_than?`
- `lib/onetime/application/request_helpers.rb:106` — `switch_organization`
- `lib/middleware/header_logger_middleware.rb` — orphaned debug middleware, never required or mounted
- `lib/middleware/locale_fallback.rb` — never mounted; self-documented as superseded by Otto native fallback + I18nLocale
- `src/tests/setup-bootstrap.ts:209` — `createHoistedWindowServiceMock` (deprecated test alias)

---

## Explicitly cleared (do not chase)

- `sendgrid-ruby` "credential path" — dead code; delivery uses raw `Net::HTTP` (`lib/onetime/mail/delivery/sendgrid.rb`), zero callers of the gem's API.
- Renovate `lockFileMaintenance` "cooldown bypass" — feature is disabled by default; setting only `{ automerge: true }` does not enable it.
- Suspended-account rejection "untested" (`base_session_auth_strategy.rb:58`) — covered by `spec/integration/all/colonel_customer_support_spec.rb:378-411`.
- UTF-8 read-without-rewind (`handle_invalid_utf8.rb:124`) — middleware `Rack::HandleInvalidUTF8` is never mounted; dead.

---

## Dependency hygiene — already resolved

The three deps/hygiene items surfaced in the first (session-limited) pass were already fixed in commit `4e7bbc130` ("Remove unused mustache gem; pin unpinned deps; deprecate ADR-001"):

- `mustache` unused production gem — removed.
- `rack-utf8_sanitizer` — now `'~> 1.11'` (`Gemfile:45`).
- `public_suffix` — now `'~> 7.0'` (`Gemfile:62`).
- `sanitize` — now `'~> 7.0'` (`Gemfile:63`).
- `truemail` — now `'~> 3.3'` (`Gemfile:68`).

The audit's deps findings were cached from the pre-commit state and are stale. Remaining optional hygiene: `httparty` (`Gemfile:52`) and `mail` (`Gemfile:61`) are still unpinned.

Informational (real, not actionable as vulns): `oauth2 2.0.25` pulls four single-maintainer micro-gems into the Google SSO token-exchange path (all share oauth2's maintainer); `brace-expansion`/`@babel/helpers` CVE pins in production `dependencies` are redundant under the pnpm-workspace overrides.
