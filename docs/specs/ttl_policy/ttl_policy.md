# TTL Policy Resolution

Design specification for collapsing secret-TTL bounds enforcement into a
single resolution point. Status: **proposed** — this documents the target
design; the code currently implements the layered model described under
"Current state".

## Problem

How long a secret may live is decided by several independent bounds that
accumulated over time. As of this writing the resolution logic exists in
multiple places and two languages:

| Layer                                               | Where                                                | Applies to                       | Kind                             |
| --------------------------------------------------- | ---------------------------------------------------- | -------------------------------- | -------------------------------- |
| `MAX_TTL` (365d)                                    | `WithEntitlements`                                   | everyone                         | absolute software-safety bound   |
| Plan `secret_lifetime`                              | org `limit_for` via `process_ttl`                    | authenticated w/ org             | billing limit                    |
| Anonymous ceiling (7d default, `TTL_MAX_ANONYMOUS`) | `configured_anonymous_max_ttl` + `anonymous_max_ttl` | anonymous                        | product policy, operator-tunable |
| Free-tier gate (14d, `DEFAULT_FREE_TTL`)            | `process_ttl` entitlement gate                       | authenticated w/ org, billing on | loud 403 w/ upgrade path         |
| `ttl_options` min/max                               | config via `process_ttl`                             | varies by branch                 | UI inventory doubling as bounds  |
| Frontend safety cap                                 | `usePrivacyOptions.ts`                               | browser UI                       | duplicate of backend policy      |

Two structural problems:

1. **Duplication across languages.** The min-of-ceilings arithmetic is
   implemented in Ruby (enforcement) and re-derived in TypeScript
   (`usePrivacyOptions.ts` filters the duration dropdown). The two can
   drift, and when they do the UI offers durations the server silently
   shortens — the exact failure mode of the 2026-07-29 API audit, item 4,
   and of #4008.
2. **Inconsistent term semantics.** `ttl_options.max` is _ignored_ when an
   org has a positive plan limit but _included_ in the anonymous minimum.
   No single mental model explains the current branches.

## Target design

### One resolver: `Onetime::TtlPolicy`

A stateless class owning every numeric TTL decision. All constants stay in
`WithEntitlements`; `TtlPolicy` becomes their only consumer.

```ruby
module Onetime
  class TtlPolicy
    Entitlements = Onetime::Models::Features::WithEntitlements

    Resolution = Data.define(:default, :min, :ceiling, :free_tier_threshold, :terms) do
      # Silent clamp used by V2/V3. Loud rejection is the caller's choice
      # (compare against .ceiling before clamping).
      def clamp(requested)
        requested.to_i.clamp(min, ceiling)
      end
    end

    # @param organization [Organization, nil] resolved org context, if any
    # @param anonymous    [Boolean] unauthenticated caller
    def self.resolve(organization: nil, anonymous: false)
      opts        = OT.conf.dig('site', 'secret_options') || {}
      ttl_options = Array(opts['ttl_options'])

      # Named terms, kept for logging so an operator can see WHICH bound
      # clamped a request ("why is my 90-day secret 45 days?").
      terms = {}

      if organization&.respond_to?(:limit_for)
        limit = organization.limit_for('secret_lifetime')
        terms[:plan_limit] = limit if limit.positive?
      end

      if anonymous
        terms[:anonymous_ceiling] = Entitlements.configured_anonymous_max_ttl
        free_tier = billing_free_tier_lifetime
        terms[:free_tier] = free_tier if free_tier&.positive?
      end

      terms[:max_ttl] = Entitlements::MAX_TTL if terms.empty?

      Resolution.new(
        default: opts['default_ttl'] || 7 * 86_400,
        min: ttl_options.min || 60,
        ceiling: terms.values.min.clamp(1, Entitlements::MAX_TTL),
        free_tier_threshold: Entitlements::DEFAULT_FREE_TTL,
        terms: terms.freeze,
      )
    end

    def self.billing_free_tier_lifetime
      return nil unless Onetime::BillingConfig.instance.enabled?
      Onetime::Organization.free_tier_limits['secret_lifetime.max'].to_i
    rescue StandardError => ex
      OT.le "[TtlPolicy] billing unavailable (#{ex.class}); free-tier term skipped"
      nil
    end
  end
end
```

### V2 enforcement collapses

`process_ttl` in `apps/api/v2/logic/secrets/base_secret_action.rb` shrinks
to: resolve, apply default, run the loud entitlement gate against
`policy.free_tier_threshold`, then `policy.clamp`. The private helpers
`anonymous_max_ttl` and `free_tier_ttl_ceiling` are deleted. V3 inherits V2
(`V3::Logic::Secrets::ConcealSecret < V2::Logic::Secrets::ConcealSecret`)
and needs no changes.

```ruby
def process_ttl
  requested = payload.fetch('ttl', nil)
  policy = Onetime::TtlPolicy.resolve(
    organization: auth_org, anonymous: anonymous_user?,
  )

  @ttl = requested.nil? ? policy.default : requested.to_i

  # Loud gate first (clear upgrade-path error beats a silent clamp), then
  # the silent clamp for everything else. Both thresholds come from the
  # same resolution — no second opinion.
  if ttl > policy.free_tier_threshold && auth_org && !auth_org.can?('extended_default_expiration')
    require_entitlement!('extended_default_expiration')
  end

  @ttl = policy.clamp(ttl)
end
```

### The serializer publishes one resolved number

`ConfigSerializer#build_secret_options` runs per-request and knows the
caller. Instead of shipping raw ingredients (`ttl_max_anonymous`, plan
limits via the organization payload) and letting TypeScript re-derive the
minimum, it ships the answer:

```ruby
policy = Onetime::TtlPolicy.resolve(
  organization: current_organization, anonymous: !authenticated?,
)
secret_options.merge(
  'ttl_ceiling' => policy.ceiling,
  # Deprecated: superseded by the resolved ttl_ceiling. Kept one release
  # for cached bundles still reading it.
  'ttl_max_anonymous' => anonymous_ttl_ceiling,
)
```

Semantic shift, stated plainly: `ttl_ceiling` means "the effective ceiling
for _this caller, this request_", not a raw config knob. That is the point
— but it is a bootstrap-contract change, hence the one-release overlap with
the legacy key.

### The frontend becomes a dumb filter

`usePrivacyOptions.ts` loses the auth branch, the organization-store read,
and the min-of-ceilings arithmetic:

```typescript
const ttlCeiling = computed<number | null>(() => {
  const value = secret_options.value?.ttl_ceiling;
  return typeof value === 'number' && value > 0 ? value : null;
});
// lifetimeOptions filters ttl_options against ttlCeiling; null fails open.
```

TypeScript can no longer disagree with Ruby about the ceiling because it
never computes one. The min-of-two-ceilings test matrix migrates to the
Ruby resolver spec; the TS spec keeps "filters by the number given" and
"fails open when absent".

## Namespacing and the policy/boundary model

`Onetime::TtlPolicy` as sketched above claims a flat top-level name for a
single policy. If more policies follow (secret size, passphrase
requirements, rate limits are the obvious candidates), the namespacing
should make room for them first — e.g. `Onetime::Policy::Ttl` (or
`Onetime::Policies::SecretLifetime`), so each policy is a sibling under one
namespace rather than a scattering of `*Policy` classes.

The underlying concept — a **policy** (the rules) evaluated inside a
**boundary container** (the scope that constrains what any policy inside it
may grant) — is the same shape as AWS's policy model, where organization-
level service control policies and permission boundaries cap what
account-level IAM policies can allow, and the effective permission is the
intersection. AWS's implementation is over-engineered for our needs, but
the principle is sound. Mapped to Onetime Secret:

- **Install/platform-level container**: the deployment's outer boundary and
  its default policy — `MAX_TTL`, the anonymous ceiling, operator config.
  Nothing inside may exceed it.
- **Organization-level policies**: plan limits and entitlements, evaluated
  inside the platform boundary. An org policy can only narrow, never widen,
  what the platform container allows.

`TtlPolicy.resolve` is the degenerate two-level case of this (platform
terms ∩ org terms, take the minimum). Naming and structuring it as
policy-within-boundary from the start keeps the door open for the other
policies without inventing a new mental model per limit.

## Deliberately out of scope

- **V1** keeps its frozen `V1_MIN_TTL`/`V1_MAX_TTL` (60s / 30 days).
  Routing V1 through the resolver would change documented legacy responses,
  which a frozen API version must not do. A pointer comment in V1 prevents
  future "helpful" unification.
- **The entitlement gate's `raise`** stays in the action — it needs
  `require_entitlement!` and request context. Only its threshold number
  comes from the resolution.

## Open decision: `ttl_options.max` as bound vs. inventory

Today `ttl_options.max` caps the anonymous path and the no-org authenticated
path, but not orgs with a positive plan limit. A min-of-all-terms resolver
cannot preserve both semantics. Recommendation: treat `ttl_options` as UI
inventory only — drop it from the ceiling terms (as the sketch above does)
and let plan/anonymous/absolute bounds do enforcement. This makes the
no-plan-limit paths cap at `MAX_TTL` for raw API callers, which is a small
loosening that needs explicit sign-off before phase 1 lands.

## Sequencing

Two PRs, so the behavior-sensitive change and the contract change get
separate review:

1. **Resolver + V2 delegation.** Behavior-identical except the
   `ttl_options.max` decision above. Table-driven resolver spec (caller
   type × term combinations) replaces the per-endpoint mock scaffolding
   for bounds logic.
2. **Serializer/frontend collapse.** Publish resolved `ttl_ceiling`,
   simplify `usePrivacyOptions.ts`, deprecate `ttl_max_anonymous` in the
   bootstrap payload; remove the legacy key one release later.

## History

- #4008: hardcoded 30-day clamp in V2 blocked self-hosted operators from
  configuring longer TTLs. Fixed minimally by deleting the redundant clamp
  (the layered bounds already enforce every real limit) and raising the
  frontend's mirrored caps to `MAX_TTL`. PR #4014 (closed unmerged)
  prototyped a configurable `TTL_CEILING` knob instead; review concluded it
  added a sixth layer rather than addressing the layering, which motivated
  this spec.
- 2026-07-29 API audit, item 4: anonymous ceiling derived from plan state
  vanished when billing was disabled; fixed with
  `configured_anonymous_max_ttl` — the pattern this design generalizes.
