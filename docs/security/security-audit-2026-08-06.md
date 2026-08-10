# Security & Code Audit — 2026-08-06

- **Repo:** onetimesecret/onetimesecret
- **Method:** Automated single-agent audit, delta-focused against the 2026-07-30 audit. Reviewed the 194 commits landed since 2026-07-31 23:59:59 (HEAD `110f9b5`), with focus on the anonymous-endpoint session-skip work (#3997/#4003), the audit-log/secret-activity terminology rename and retention-cap work (#3977/#3985/#3990), IP/proxy documentation changes, the domains-config serializer boundary (#3998), the Familia 2.12 dependency bump, and billing/Stripe code. Every finding below was verified by reading current source, not inferred from commit messages.

---

## Bottom line

No new Critical/High/Medium security defects were confirmed in this window. Notably, the two riskiest changes in the delta — session-skip path matching and the `ORGS_AUDIT_LOGS_ENABLED` boolean-coercion gate — each shipped with a genuine bug and were fixed by a later commit in the _same_ window, before this audit ran. Those are recorded below under "Self-corrected within the window" per this routine's convention of documenting refutations/closures so they aren't re-litigated next time. One Low-severity, non-security finding (a revenue/compliance regression in Stripe tax collection) is worth operator attention.

---

## Findings

### 1. LOW (functional, not security) — Stripe automatic tax silently flipped from always-on to opt-in

**Files:** `apps/web/billing/controllers/plans.rb`, `apps/web/billing/operations/create_checkout_link.rb` (`apply_tax_policy!`), gated by `lib/onetime/billing_config.rb` (`automatic_tax?`)

Commit `d847cce` ("refactor(billing): centralize Stripe checkout session parameters in shared builder") removed the hardcoded `automatic_tax: { enabled: true }, tax_id_collection: { enabled: true }` from `Plans#checkout_redirect` and replaced it with `Billing::Operations::CreateCheckoutLink.apply_tax_policy!(session_params)`, which is a no-op unless `ENV['STRIPE_AUTOMATIC_TAX']` or `billing.yaml`'s `automatic_tax` key is truthy (default `false`). Before this change, every self-serve checkout session unconditionally requested Stripe Tax; after it, a deployment that doesn't set `STRIPE_AUTOMATIC_TAX=true` stops collecting/reporting VAT/GST on new subscriptions with no error, warning, or log line. Not a security vulnerability — no auth bypass, no data exposure — but a silent behavior change hidden inside a "refactor" commit.

**Recommendation:** Confirm the hosted onetimesecret.com production environment has `STRIPE_AUTOMATIC_TAX=true` set; if not, tax collection has been silently disabled since `d847cce` landed. Consider a boot-time log line (parallel to the `skip_paths` boot-log precedent in `boot.rb:235`) surfacing the resolved tax policy so a misconfiguration is visible.

**Update 2026-08-07:** Partly overtaken by the #4013 work — `STRIPE_AUTOMATIC_TAX` is now documented (`93abc98c`) and boot validation covers the `STRIPE_AUTOMATIC_TAX`/`BILLING_ENABLED` combination. Issue #4025 tracks the related currency-migration no-tax defect. Still open: confirming the production env var, and the boot-time log of the resolved tax policy.

---

## Self-corrected within the window (verified fixed, not re-flagged)

- **Session-skip / health-gate path-canonicalization bypass (#3997).** `aa4aab4` introduced `Onetime::Middleware::SessionSkip` and touched `HealthAccessControl`, both matching the raw request path. `312b5e0` ("Normalize probe and health path matching to Otto router canonicalization") fixes the gap: `GET /api/v2/status/` or `/api/v2/%73tatus` reached the status handler (Otto's router unescapes and trims one trailing slash before dispatch) while dodging `SessionSkip`'s raw-string match, re-opening the per-probe session-mint leak; and `GET /health%2Fadvanced` from a public IP bypassed `HealthAccessControl`'s private-network gate entirely. Current code (`lib/onetime/middleware/session_skip.rb:106-107`, `lib/onetime/middleware/health_access_control.rb:107-110`) both call the same shared `Otto::Utils.normalize_path` the router uses at dispatch time, so router-dispatch and gate-match can no longer canonicalize differently. Checked the `commit_session` `:drop`/`:renew`-before-`:skip` caveat the code's own comments flag — no configured `skip_paths` entry overlaps a login/logout/password-rotation route today. Confirmed none of the skip_paths routes are POST-able or CSRF-relevant, so `CsrfResponseHeader`'s read-only gate cannot weaken CSRF protection anywhere.
- **`ORGS_AUDIT_LOGS_ENABLED` string/boolean coercion mismatch between enforcement and UI (#3985).** `a782364` added the backend gate with `OT.conf.dig(...) == false` — a hand-edited config yielding the string `'false'` would NOT trip this. `28d4d0d` fixed the serializer to `.to_s != 'false'`; `0249eae` fixed the API enforcement in `list_secret_activity.rb:70` to the matching `.to_s == 'false'` form, in the same window. Verified current source on both sides uses the string-safe comparison.
- **`SecretActivity` retention cap: verified atomic, verified not bypassable.** `9d65e5a` replaced a two-round-trip `zadd` + `remrangebyrank` (a real race window) with Familia 2.12's `max_length:` sorted-set option, which wraps the write and the trim in one MULTI (`capped_zadd_write`). Checked every call site of `secret_activity_events` — only `.add` is ever called; the uncapped paths (`unionstore`/`interstore`/`diffstore`/`restore`) are unused, so the cap cannot be bypassed.

---

## Reviewed, no issue found

- **`list_secret_activity.rb` authorization completeness.** `require_entitlement_in!(@organization, 'audit_logs')` enforces active org membership + plan entitlement server-side, independent of and stricter than the frontend tab-hiding. No other endpoint exposes `SecretActivity` data; the colonel `ListColonelAuditEvents` endpoint reads a different model gated by `verify_one_of_roles!(colonel: true)`.
- **`AdminAuditEvent` → `ColonelAuditEvent` rename (#3977).** Mechanical; zero dangling references to the old name. Cap semantics and the "unauthenticated writer must have a per-window bound" invariant carried through unchanged.
- **Domains-config serializer boundary (#3998).** `transform_domains` is a genuine 4-key allowlist. `build_safe_features_config`'s new scrub is defense-in-depth behind that allowlist, not the primary gate. No other code path reads the raw `features.domains` subtree.
- **Familia 2.12 bump (read-side encryption rotation prep).** `configure_familia.rb` makes no writer-behavior change: existing salt/personalization values are pinned byte-for-byte; the new rotation-history knob is deliberately left unset. No onetimesecret code depends on the new multi-candidate decrypt-fallback semantics yet.
- **IP/proxy handling.** All commits in this window under this heading touch only example configs and docs; the actual trusted-proxy logic in `middleware_stack.rb` was untouched. The 2026-07-30 audit's residual (client-IP attribution depends on correct deployment-side trusted-proxy config) remains open and is now documented more precisely — not a regression.
- **Billing/Stripe authorization.** `CreateCheckoutLink` gates on `verify_one_of_roles!(colonel: true)` and blocks link creation for orgs with an already-active subscription. No webhook/signature-verification code was touched in this window.
- **General sweep.** No `Marshal.load`, unsafe `YAML.load`, `eval`, `system(`, or `instance_eval` on untrusted input in any `.rb` file touched in this window; no SQL string-interpolation patterns found.
