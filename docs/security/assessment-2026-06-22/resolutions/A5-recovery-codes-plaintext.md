# A5 — Recovery codes stored in plaintext in SQL

- **Severity:** Medium (high impact: recovery codes are a full MFA-bypass credential)
- **Status:** Proposed fix
- **Affects default config?** No — gated on auth being enabled (Rodauth full-auth mode) **and** MFA
  (`otp`/`recovery_codes`) enrolled by the user. Recovery codes only exist once a user sets up TOTP/WebAuthn.
- **Related:** A13 (64-bit recovery-code entropy — fix alongside), finding 01 §5/§13. MFA config in
  `apps/web/auth/config/features/mfa.rb`.
- **Primary files:**
  - `apps/web/auth/config/features/mfa.rb` (OTS override point — add storage/compare overrides here)
  - fork `rodauth/lib/rodauth/features/recovery_codes.rb` (stores/compares verbatim — root cause)
  - fork `rodauth/lib/rodauth/features/base.rb` (`compute_hmac`, `timing_safe_eql?`, `random_key` helpers)
  - DB migration for `account_recovery_codes` (new, under the app's auth migrations dir)

## Problem (recap)

Recovery codes are written to and read from SQL **verbatim** — there is no hash or HMAC at rest, unlike
password hashes (argon2) and OTP keys (which OTS HMAC-wraps via `otp_keys_use_hmac? true`,
`mfa.rb:31`). Anyone with read access to the auth DB (compromise, backup leak, SQLi, broad console
access) obtains working second-factor bypass codes for every MFA-enrolled account.

Evidence (fork `recovery_codes.rb`):

```ruby
# Insert — stores new_recovery_code as-is (recovery_codes.rb:189-196)
def add_recovery_code
  retry_on_uniqueness_violation do
    recovery_codes_ds.insert(recovery_codes_id_column=>session_value,
                             recovery_codes_column=>new_recovery_code)   # cleartext
  end
end

# Compare — pulls raw stored values and compares the raw param (recovery_codes.rb:162-173)
def recovery_code_match?(code)
  recovery_codes.each do |s|
    if timing_safe_eql?(code, s)                                        # raw vs raw
      recovery_codes_ds.where(recovery_codes_column=>code).delete
      ...
    end
  end
end

# Read-back — select_map of the raw column (recovery_codes.rb:262-264)
def _recovery_codes
  recovery_codes_ds.select_map(recovery_codes_column)
end
```

OTS only overrides the **generator** (`new_recovery_code { Familia.generate_trace_id }`, `mfa.rb:74-76`),
not storage or comparison.

## Root cause

Neither this Rodauth fork **nor** upstream `rodauth 2.42.0` implements any hashing/HMAC of recovery
codes — verified by grep over both `recovery_codes.rb` files (no `hmac`/`hash`/`compute_hmac`
reference). So there is **no built-in `recovery_codes_hmac`-style toggle to flip**; the codes are
inherently stored exactly as `new_recovery_code` returns them. The fix must override the
store/read/compare methods in OTS config.

> **Confirm first (was NEEDS-VALIDATION on the "rodauth supports hashing" assumption):** The original
> finding suggested Rodauth "supports hashing recovery codes." It does **not** in the version on disk.
> Before implementing, confirm no newer fork branch adds it; if it does, prefer the upstream toggle over
> a local override. As of the reviewed tree, the override below is required.

## Prescribed resolution

Store a **keyed HMAC** (HMAC-SHA256 under the existing `AUTH_SECRET`-derived `hmac_secret`) of each
recovery code; never persist the cleartext. Display the cleartext to the user exactly once at
generation time (it is already shown only in the add/view response). Compare by HMAC-ing the submitted
code and constant-time matching against stored HMACs.

HMAC (keyed) is preferred over a plain hash here: recovery codes are short, so an unkeyed
SHA-256 of a 64-bit code is offline-brute-forceable; the keyed HMAC ties recovery to `AUTH_SECRET`
(defense-in-depth identical to the OTP-key and email-token treatment OTS already relies on). Use the
Rodauth-provided `compute_hmac` (fork `base.rb:279`) so secret rotation semantics match the rest of the
stack.

### Implementation steps

1. **Add override methods in `apps/web/auth/config/features/mfa.rb`.** Override storage and comparison so
   the column always holds an HMAC. Because the feature reads codes back in several places
   (`recovery_codes`, `_recovery_codes`, `recovery_code_match?`), override at the lowest seam —
   `add_recovery_code` (store) and `recovery_code_match?` (compare):

   ```ruby
   # apps/web/auth/config/features/mfa.rb — inside MFA.configure(auth)

   # Store only the HMAC of the code. The cleartext is surfaced to the user via
   # the add-recovery-codes response; we never persist it.
   auth.add_recovery_code do
     retry_on_uniqueness_violation do
       code = new_recovery_code                         # cleartext, shown to user
       stash_plaintext_recovery_code(code)              # for the one-time view (see step 2)
       db[recovery_codes_table].insert(
         recovery_codes_id_column => session_value,
         recovery_codes_column    => compute_hmac(code) # HMAC-SHA256 under AUTH_SECRET
       )
     end
   end

   # Compare by HMAC-ing the submitted code against stored HMACs (constant-time),
   # then delete the matched row by its stored HMAC value.
   auth.recovery_code_match? do |code|
     hashed = compute_hmac(code)
     stored = db[recovery_codes_table]
                .where(recovery_codes_id_column => session_value)
                .select_map(recovery_codes_column)
     stored.each do |s|
       next unless timing_safe_eql?(hashed, s)
       db[recovery_codes_table]
         .where(recovery_codes_id_column => session_value,
                recovery_codes_column    => s).delete
       add_recovery_code if recovery_codes_primary?      # preserve fork behavior
       return true
     end
     false
   end
   ```

   Note: `compute_hmac` is deterministic for a given `AUTH_SECRET`, so equality search and the
   delete-by-value both work against the stored HMAC. `timing_safe_eql?` (fork `base.rb:726`) keeps the
   compare constant-time, matching the original code's intent.

2. **Preserve one-time display of the cleartext.** The add/view flow shows the codes to the user once.
   Since the column now holds HMACs, the response builder can no longer read the cleartext back from the
   DB. Capture the freshly generated cleartext codes in a request-scoped accumulator
   (`stash_plaintext_recovery_code`) and have the view/JSON response read from it for the
   add-recovery-codes response only. After the request, the cleartext is gone; the "View recovery codes"
   route can no longer re-display old codes (this is a deliberate, correct hardening — see Alternatives).

3. **DB migration — re-key existing rows.** Add a migration that HMACs any existing cleartext rows in
   `account_recovery_codes` in place:
   - Read each `(id, code)`; if the value does not already look like an HMAC (see step 4 marker),
     `UPDATE ... SET code = HMAC(code)`.
   - Run inside the app (Ruby migration calling `rodauth.compute_hmac`) rather than raw SQL, so the same
     keyed HMAC is applied. Do this as an offline/maintenance migration, not a live request path.

4. **Disambiguate already-migrated rows.** HMAC output is fixed-length hex/base64; cleartext trace IDs
   are base36 ~13 chars. Detect "already HMAC" by length/charset, or add a one-time schema marker column
   (`code_format`), defaulted to `:hmac` for new rows, so the migration is idempotent and re-runnable.

5. **Operational controls (independent of code).** Enforce DB-at-rest encryption and tight access on
   `account_recovery_codes` and its backups; ensure `AUTH_SECRET` is set and strong (cross-ref the
   `hmac_secret_guard` boot assertion discussed in finding 01 §12 — if `AUTH_SECRET` is unset, `compute_hmac`
   has no key and this mitigation degrades).

### Alternatives considered

- **Flip a built-in Rodauth toggle:** rejected — no such toggle exists in the fork or upstream 2.42
  (verified). Would require upgrading/forking Rodauth itself; the local override is lower-risk and
  self-contained.
- **Unkeyed SHA-256 instead of HMAC:** rejected — recovery codes are short (64-bit, A13), so an unkeyed
  digest is offline-brute-forceable from a DB dump. Keyed HMAC under `AUTH_SECRET` removes the offline
  attack and mirrors the existing OTP-key/email-token treatment.
- **Argon2/bcrypt per code:** rejected — recovery codes are server-side, rate-limited, single-use, and
  account-bound; a memory-hard KDF per code adds cost without materially improving on a keyed HMAC for
  this threat (DB read), and complicates the equality search.
- **Keep cleartext but rely on DB encryption only:** rejected — at-rest DB encryption does not protect
  against SQLi, console access, or logical backup leaks; app-layer HMAC is defense-in-depth on top.

### Combine with A13

Since this change rewrites `new_recovery_code`'s storage path, raise entropy at the same time: replace
`Familia.generate_trace_id` (64-bit) with a 128-bit CSPRNG code (e.g. `random_key`-derived or
`SecureRandom`), keeping a user-friendly base32/base36 rendering. One migration covers both A5 and A13.

## Test / verification

Add to `apps/web/auth/spec/` (integration + unit):

1. **At-rest is HMAC, not cleartext:** enroll TOTP (auto-adds recovery codes via
   `auto_add_recovery_codes? true`, `mfa.rb:50`); assert the `account_recovery_codes.code` column for the
   account contains **no** value equal to any code shown in the add response, and that each stored value
   equals `rodauth.compute_hmac(shown_code)`.
2. **Auth still works:** submit a valid cleartext recovery code to the recovery-auth route → succeeds,
   row is deleted, MFA satisfied; submit a used/garbage code → fails (no enumeration of remaining count).
3. **Constant-time compare path** is exercised (no early-return on first byte) — assert via the
   `timing_safe_eql?` call, not wall-clock timing.
4. **Migration idempotency:** seed legacy cleartext rows; run migration once → values become HMACs and
   still authenticate; run again → no double-HMAC (idempotent via the marker/charset check).
5. **One-time display:** after generation, the "view recovery codes" route does not re-expose the
   original cleartext (confirms step 2's intended behavior change).
6. **Regression:** `auto_remove_recovery_codes?`/`recovery_codes_primary?` paths (`mfa.rb:56`,
   fork `recovery_codes.rb:246-260`) still behave; primary-mode top-up after a match still works.

## Effort & risk

- **Effort:** Medium. Two method overrides + a one-time-display accumulator + an idempotent data
  migration. No new dependency; reuses `compute_hmac`/`timing_safe_eql?`.
- **Risk:** Medium. The behavior change (codes no longer re-displayable after creation) is a UX shift —
  document it ("save these now; they cannot be shown again"). Migration must run before deploy or codes
  briefly mismatch; gate behind a maintenance window or make `recovery_code_match?` accept either raw or
  HMAC during a short transition, then drop the raw branch. Low regression risk for non-MFA users
  (no recovery codes exist).
