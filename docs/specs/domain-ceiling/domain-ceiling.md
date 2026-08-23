# Custom Domain Creation Ceiling + Velocity Limit

Status: Draft — 2026-08-21
Related: #3491 (M9 numeric-limit overrides, M10 free_tier drift), #4215
(domains drift guard / `bin/ots domains repair`)

Free orgs are advertised one custom domain but may add more. Today nothing
enforces any count, and nothing bounds how fast domains are created. This
spec adds two complementary, independent controls:

1. **Ceiling** — a per-org maximum that is deliberately higher than the
   advertised plan limit. Abuse backstop, operator-adjustable per org.
2. **Velocity** — a per-org creation rate limiter on the established
   `lib/onetime/security/*_rate_limiter.rb` pattern.

Neither changes what is advertised.

---

## 1. Constraint that shapes the design

`limits_plan` cannot carry a per-org numeric override. Both materialization
writers do `limits_plan.clear` then re-copy from the plan
(`organization/features/with_materialized_entitlements.rb:127-128` from
`Billing::Plan`, `:159-160` from config fallback). Entitlement overrides
survive only because `entitlements_grants` / `entitlements_revokes` are
separate collections no reconcile path clears. There is no `limits_grants`
equivalent. So "operator grants more" needs storage that materialization
never touches.

## 2. Advertised vs enforced

`limits.custom_domains: 1` in `billing.yaml` stays the advertised number: it
is the product promise, stays in `limit_for`, stays in both serializers
(`organization/features/safe_dump_fields.rb:60`,
`apps/web/core/views/serializers/organization_serializer.rb:161`), stays what
the UI shows. It is NOT overloaded with enforcement.

Enforcement ceiling is **site config, not a plan key**. Plan limits are
pushed to Stripe and become product surface; this is an ops knob.

```yaml
# etc/defaults/config.defaults.yaml — under features.domains (NOT site.domains;
# features.domains is where enabled/require_verified/default/link_domains live)
features:
  domains:
    # Abuse backstop, NOT the advertised plan limit. Set to 1 to enforce
    # exactly what billing.yaml advertises for free.
    creation_ceiling: <%= ENV['DOMAINS_CREATION_CEILING'] || 25 %>
```

Env naming follows siblings `DOMAINS_ENABLED`, `DOMAINS_REQUIRE_VERIFIED`.

### Resolution rule

```
advertised = org.limit_for(:custom_domains)      # may raise PlanCacheMissError — let it propagate
ceiling    = org.limits_overrides['custom_domains.max'] || conf.features.domains.creation_ceiling
enforced   = advertised == ∞ ? ∞ : [advertised, ceiling.to_i].max
blocked    = org.domain_count >= enforced
```

Properties:

- Unlimited tiers (`identity_plus_v1: custom_domains: -1`) stay unlimited;
  the backstop never undercuts what was paid for.
- A finite paid tier advertising 100 enforces 100, not 25.
- "Enforce the advertised limit" is `DOMAINS_CREATION_CEILING=1`. No code
  change, no plan re-push.
- The per-org override replaces the **site ceiling** in the max, not the
  advertised number. An operator can clamp an abusive org below 25
  (override=1) without banning, and can never clamp below the promise.
- Standalone (billing disabled): `limit_for` returns ∞, so ceiling and
  override are dead letters. The override op surfaces `standalone: true`
  exactly as `Operations::Org::EntitlementOverride` does (D17).

Count source: `org.domain_count` (`organization.rb:230`, ZCARD on the
auto-generated `domains` zset), not `list_domains.size` (load_multi). Stale
zset refs overcount, which fails toward blocking — acceptable;
`bin/ots domains repair` exists for drift.

### Override storage

`hashkey :limits_overrides` on Organization, declared beside `limits_plan` in
`WithMaterializedEntitlements`, keyed by the same flattened limit key
(`'custom_domains.max'`). Chosen over a scalar `:domain_ceiling_override`
field: identical cost, survives materialization by construction (new
collection), and it IS the missing `limits_grants` — when #3491 M9 lands
nothing is renamed. `limit_for` does NOT consult it; only the enforcement
resolver reads it. That is what keeps the advertise/enforce split.

Written by `Onetime::Operations::Org::LimitOverride` (set/clear, audit
backstop in the op, `standalone:` on Result), modeled on
`EntitlementOverride`. Adapters: colonel endpoint + `bin/ots org limit`.
Named by what it stores, not by domains.

## 3. Velocity limiter

`lib/onetime/security/domain_creation_rate_limiter.rb` on the
`CreateAccountRateLimiter` shape: Lua `CHECK_AND_RECORD_SCRIPT` (atomic
check + increment, denied tier never incremented), config-gated, audit verb
on the cap-reaching request only.

- **Subject: organization objid, single tier.** Not IP. Route is
  `auth=sessionauth` and org-scoped; the resource owner is the natural
  bucket and it avoids the masked-/24 collapse that forces
  `CreateAccountRateLimiter` loose. Account fan-out is bounded by
  composition: free caps at 1 org (after the §5 fix), `create_account_ip`
  caps signups at 10/hr/masked-IP.
- **Defaults: 10/hour, 1h window, 1h lockout.** Not 5. With ceiling=25 the
  limiter barely matters for free orgs; its job is bounding cert-provisioning
  burst (Approximated/Caddy request, favicon job, DNS) from unlimited tiers —
  the accounts doing legitimate bulk migrations. 5 turns a paid customer's
  6-domain onboarding into a lockout and a ticket.
- Config: `features.domains.creation_rate_limit: {enabled, max_per_org,
  window, lockout}`; `DOMAINS_CREATION_RATE_LIMIT_ENABLED`, default on.
  `spec/config.test.yaml` sets `enabled: false` like
  `create_account_rate_limit`.
- Keys: `domain_create:attempts:org:%s`, `domain_create:locked:org:%s`.
- `Operations::Ratelimit::Registry::LIMITERS['domain_create_org']`,
  subject `'organization objid'`, `dbclient: -> { Onetime::CustomDomain.dbclient }`
  (same shard as `dns`). Gives `bin/ots ratelimit keys` and
  `POST /api/colonel/ratelimit/reset` for free.
- Audit verb: `domains.create_throttled`.
- Fail semantics: Redis errors propagate (no silent permit).

## 4. Gate placement

Both in `AddDomain#raise_concerns`
(`apps/api/domains/logic/domains/add_domain.rb`):

1. **Ceiling** immediately after `require_entitlement_in!(@target_organization,
   'custom_domains')` — cheap, deterministic, should not burn velocity budget.
2. **Velocity** as the **last line** of `raise_concerns`, after the
   `existing` (already-in-org / other-org) checks. CHECK_AND_RECORD
   increments on check; a re-add or typo must not cost budget. CreateAccount
   charges malformed submissions because they are free to generate and
   equally good for flooding; here malformed/duplicate requests create
   nothing, and the protected resource is creation, not request handling.

NOT in `CustomDomain.create!`. The canonical-overlap check there is an
integrity backstop; this is policy — and console/CLI
(`Operations::Domains::Create`, colonel `POST /api/colonel/domains`,
`bin/ots domains create`) is precisely the "operator grants more" path.
Untouched.

## 5. Fix in the same change

1. `WithPlanEntitlements.free_tier_limits`
   (`organization/features/with_plan_entitlements.rb:125`) has no
   `custom_domains.max`, so `free_tier_limit_for` returns its unknown-key
   default 0 and a billing-enabled, not-yet-materialized org serializes
   `custom_domains: 0`. Add `'custom_domains.max' => 1`. Fix the M10 drift
   in the same hash: `'organizations.max' => 5` → `1` (YAML says 1; the
   §3 fan-out argument depends on it). Leave `secrets_per_day` out (YAML:
   not yet enforced).
   Spec fallout: `spec/unit/onetime/models/features/with_entitlements_ttl_env_spec.rb:200,223`
   assert 5. `with_materialized_entitlements_spec.rb` hits are fixture
   literals; `create_organization_spec.rb` stubs `at_limit?`.
2. Error copy must not say "upgrade your plan" — someone hitting 25 when the
   UI advertises 1 is 24 past it. Ceiling:
   `raise_form_error(error_key: 'api.domains.errors.domain_ceiling_reached',
   field: 'domain', error_type: :forbidden)` — explicitly not
   `:upgrade_required` (`create_organization.rb:173` uses that to drive the
   upgrade CTA). Copy: "Maximum domains reached for this account. Contact
   support to request more." Velocity: `Onetime::LimitExceeded` with
   `retry_after` — `otto_hooks.rb:80` maps to 429, `error_correlation.rb`
   rounds `retry_after` up to minutes. Copy: "Too many domains added
   recently. Try again in N minutes." Locale keys
   `api.domains.errors.domain_ceiling_reached`,
   `api.domains.errors.rate_limit_exceeded`, all locales.

## 6. Invariant: the split must stay invisible

Nothing in `src/` compares `limits.custom_domains` against the actual count
(`schemas/contracts/organization.ts:102`, `config/billing.ts:168` only
carry it). `useEntitlements.ts:105` `limit(resource)` is typed to accept
`custom_domains` but has no caller for it. Keep it that way — the moment
something renders "3 of 1 used" the split is visible. Comment on the getter
and on both serializers.

## 7. Out of scope

- General numeric-limit overrides (#3491 M9). `limits_overrides` is the
  storage for it; the read path in `limit_for` is not built here.
- Per-IP or per-customer velocity tiers.
- Enforcing `secrets_per_day`.

## 8. Checklist

- [ ] `features.domains.creation_ceiling` + `creation_rate_limit` in defaults; test config disables limiter
- [ ] `hashkey :limits_overrides` beside `limits_plan`
- [ ] `Operations::Org::LimitOverride` + colonel endpoint + `bin/ots org limit`
- [ ] `security/domain_creation_rate_limiter.rb` + `try/unit/security/domain_creation_rate_limiter_try.rb`
- [ ] `Registry::LIMITERS['domain_create_org']`
- [ ] `AddDomain#raise_concerns`: ceiling after entitlement, velocity last
- [ ] `free_tier_limits`: add `custom_domains.max => 1`, fix `organizations.max => 1`; update ttl_env spec
- [ ] Locale keys ×2, all locales; `scripts/i18n` hashes
- [ ] Invariant comments (§6)
