# C5 — No application-level cap on secret payload size

- **Severity:** Low (DoS / resource exhaustion) — **CONFIRMED** in source
- **Status:** Proposed fix
- **Affects default config?** **Yes** — anonymous secret creation accepts arbitrarily large values
- **Related:** finding 03 F5; plan-limit plumbing in
  `lib/onetime/models/organization/features/with_materialized_limits.rb` (`limit_for`)
- **Primary files:** `apps/api/v2/logic/secrets/base_secret_action.rb`,
  `apps/api/v2/logic/secrets/conceal_secret.rb`,
  `lib/onetime/models/receipt.rb` (`spawn_pair`), `etc/config.yaml` (`secret_options`)

## Problem (recap)

`ConcealSecret` / `BaseSecretAction` validate TTL, passphrase length, recipient, and share domain,
but **never bound the byte size of the secret value itself**. `ConcealSecret#raise_concerns` only
rejects an *empty* value:

```ruby
# apps/api/v2/logic/secrets/conceal_secret.rb:26-29
def raise_concerns
  require_guest_route_enabled!(:conceal)
  super
  raise_form_error 'You did not provide anything to share', field: :secret, error_type: :missing if secret_value.to_s.empty?
end
```

`BaseSecretAction` bounds `passphrase` length (`base_secret_action.rb:289-299`) but has **no**
value-size check anywhere (confirmed: only `passphrase` and the unrelated `memo`/`MEMO_MAX_LENGTH`
are bounded). The value flows straight into storage: `create_secret_pair` →
`Onetime::Receipt.spawn_pair(...)` → `secret.ciphertext = content` → `secret.save`
(`base_secret_action.rb:329-335`, `receipt.rb:226,233`), where it is encrypted and stored as a Redis
hash field with a TTL.

## Root cause

Payload size is treated as the deployment proxy's concern, not the application's. No Rack/body limit
was found in-repo, so the only backstops are (a) whatever the upstream web server / reverse proxy
imposes and (b) the per-secret TTL (secrets expire — default 7 days, `base_secret_action.rb:113`).
There is no app-level ceiling, and no tie-in to plan limits, so an unauthenticated client can store
very large blobs.

## Impact

Bounded but real: an attacker (especially anonymous, where there is no account to throttle) can
inflate Redis memory by creating large secrets faster than they expire, amplifying memory/cost
pressure. AEAD encryption (`manager.rb:17-23`) also copies the plaintext in memory during encryption,
so very large values cost CPU/RAM per request. Mitigated by TTL and any proxy body limit, but those
are not guaranteed and not under app control.

## Prescribed resolution

Enforce a **maximum byte size** on the secret value in the shared base action, returning a form
error above the limit, and tie the ceiling to plan limits where billing is enabled. Centralise the
check in `BaseSecretAction` so it covers `ConcealSecret`, `GenerateSecret`, and any future
sub-action.

### Implementation steps

1. **Add a config knob** under the existing `secret_options` block (`etc/config.yaml:198-220`,
   alongside `default_ttl`, `ttl_options`, `passphrase:`). Use bytes and an ENV override consistent
   with the file's style:

   ```yaml
   secret_options:
     # Maximum size (bytes) of a single secret's plaintext value. Guards Redis
     # memory against oversized payloads. Measured on the UTF-8 byte length.
     max_value_size: <%= ENV['SECRET_MAX_VALUE_SIZE'] || 256000 %>   # 256 KB default
   ```

   256 KB is a suggested default — generous for passwords/keys/notes, modest for Redis. Confirm an
   appropriate value with the maintainer for the product's real use cases.

2. **Validate in `BaseSecretAction`.** Add a `validate_secret_size` and call it from
   `raise_concerns` (`base_secret_action.rb:41-48`), after `kind` is known so the error is
   value-neutral about *which* sub-action ran. Measure **bytesize**, not character length (UTF-8
   multibyte and binary blobs):

   ```ruby
   def raise_concerns
     require_entitlement!('api_access')
     raise_form_error 'Unknown type of secret' if kind.nil?

     validate_secret_size
     validate_recipient
     validate_share_domain
     validate_passphrase
   end

   # Bytes, not chars — a UTF-8 value's char count understates Redis cost.
   def validate_secret_size
     size  = secret_value.to_s.bytesize
     limit = max_secret_value_size
     return if size <= limit

     raise_form_error "Secret is too large (#{size} bytes; maximum #{limit}).",
       field: :secret, error_type: :too_large
   end
   ```

3. **Resolve the limit, plan-aware.** Mirror the `process_ttl` pattern
   (`base_secret_action.rb:103-110`), which already uses `auth_org.limit_for('secret_lifetime')`
   with a config fallback and fails open (unlimited) when billing is off:

   ```ruby
   def max_secret_value_size
     config_max = (OT.conf.dig('site', 'secret_options', 'max_value_size') || 256_000).to_i

     if auth_org && auth_org.respond_to?(:limit_for)
       plan_max = auth_org.limit_for('secret_value_size')  # billing.yaml limit, if defined
       return plan_max if plan_max.is_a?(Numeric) && plan_max.positive? && plan_max != Float::INFINITY
     end
     config_max
   end
   ```

   `limit_for` already returns `Float::INFINITY` when billing is disabled (self-hosted/standalone,
   `with_materialized_limits.rb:68-70`), so self-hosters keep the config ceiling rather than being
   forced to a plan. If you add a `secret_value_size` limit to `etc/billing.yaml` plans, paid tiers
   can raise it; if you do not, the config default governs everyone. **Confirm first** whether plan
   tiering of payload size is desired before adding the billing key — the config-only ceiling is the
   minimum viable fix and is enough to close the DoS.

4. **Keep the empty-value check** in `ConcealSecret` (`conceal_secret.rb:29`) — size validation is
   the upper bound; the empty check is the lower bound. They are complementary.

### Defense-in-depth (recommended, separate from the app fix)

Document a reverse-proxy / Rack body-size limit in the deployment runbook as a first line of defense
so oversized requests are rejected before reaching Ruby. The app-level cap is the authoritative one,
but a proxy limit avoids buffering huge bodies into the worker at all.

### Alternatives considered

- **Rely on a proxy body limit only.** Rejected: not present in-repo, not guaranteed across
  deployments, and gives no plan-aware behaviour or clean form error.
- **Character-length limit.** Rejected: understates Redis cost for multibyte/binary content;
  `bytesize` is the correct measure.
- **Truncate silently.** Rejected: silently dropping secret content is dangerous (the user thinks
  they shared the whole thing). A hard error is correct.

## Test / verification

- **Over-limit:** submit a value 1 byte over `max_value_size` → assert `too_large` form error and
  that no `Secret`/`Receipt` was created (assert `spawn_pair` not reached / no new keys).
- **At-limit:** submit exactly `max_value_size` bytes → succeeds.
- **Bytesize correctness:** a multibyte UTF-8 string whose char count is under but byte count is over
  the limit → rejected (guards against measuring `.length` instead of `.bytesize`).
- **Plan-aware (if billing key added):** org with a higher `secret_value_size` limit accepts a value
  that a free org rejects; billing-disabled deployment falls back to the config ceiling.
- **Empty still rejected:** ensure the existing empty-value error
  (`conceal_secret.rb:29`) is unaffected.

## Effort & risk

- **Effort:** Low. One config key, one validation method in the shared base, optional billing key.
- **Risk:** Low. Purely additive validation on the create path; existing valid secrets are
  unaffected. The only behavioural change is rejecting oversized payloads, which is the intent.
  Choose the default limit deliberately so legitimate large-but-valid secrets are not broken.
- **Priority:** Low — bundle with C4/C6 after the higher-severity items.
