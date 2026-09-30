---
labels: authorization, entitlements, verification, scientist, issue-3491
related: "#3491, issue-3491-plan-entitlements-vs-role-capabilities.md, docs/specs/billing-decoupling/provider-seam-verification.md"
status: proposal / companion
---

# Production-Parity Verification for the Plan/Role Split (Scientist companion)

> Companion to `issue-3491-plan-entitlements-vs-role-capabilities.md` (the
> "prep doc"). That document says what changes and in what order. This one
> says how each stage proves it did not change anything it was not supposed
> to, using the [`scientist`](https://github.com/github/scientist) gem to run
> the new derivation beside the old one on production reads. It also defines
> the shared experiment harness that the billing provider work reuses
> (`docs/specs/billing-decoupling/provider-seam-verification.md`).

## 0. What Scientist proves, and what it does not

Scientist runs a `control` (current code) and a `candidate` (new code) on the
same input, returns the control's result to the caller, and publishes whether
the two agreed. The candidate's exceptions are swallowed and published. That
gives one specific proof: on the inputs production actually sees, the new
derivation returns the same answer as the old one, or it returns a different
answer at a recorded input that can be triaged.

It fits the #3491 work because every predicate in scope is a pure read over
Redis state: `can?`, `entitlements`, `limit_for`, the intersection in
`materialize_for_role!`, and the fallback in `compute_entitlements_from_role`.
No candidate here needs to write or call out.

It does not prove that the *intended* behaviour changes are correct. Stage C
changes access on purpose at every site listed in the tier-preservation
decision list (prep doc §6 Stage B). Scientist's job there is to guarantee that
every observed access change has a ruling, not that the ruling is right.

Volume caveat: at OTS's scale, a predicate that runs on every authenticated
request accumulates a useful sample in hours; one that runs on role change or
webhook delivery takes days to weeks. Exit criteria below are phrased as
"observed population" rather than elapsed time.

## 1. Shared harness

### 1.1 Dependency and base class

Add `scientist` to the Gemfile (plain Ruby, no dependencies, no Rails
coupling). Define one base class so publish, cleaning and context are uniform:

```ruby
# lib/onetime/experiment.rb
require 'scientist'

module Onetime
  class Experiment
    include Scientist::Experiment

    # name: dotted, stage-qualified. e.g. 'ent.stage_b.feature_gate'
    # See §1.4 for the registry that owns removal.
    def initialize(name)
      @name = name
    end

    attr_reader :name

    def enabled?
      Onetime::ExperimentRegistry.enabled?(name)
    end

    def publish(result)
      payload = {
        experiment: name,
        matched:    result.matched?,
        mismatched: result.mismatched?,
        ignored:    result.ignored?,
        control:    result.control.cleaned_value,
        candidate:  result.candidates.map(&:cleaned_value),
        cand_error: result.candidates.map { |c| c.exception&.class&.name }.compact,
        control_ms: (result.control.duration * 1000).round(2),
        cand_ms:    result.candidates.map { |c| (c.duration * 1000).round(2) },
        context:    context,
      }
      OT.li "[experiment] #{payload.to_json}"
      return unless result.mismatched? || result.candidates.any?(&:raised?)
      return unless defined?(Sentry) && Sentry.initialized?

      Sentry.with_scope do |scope|
        scope.set_fingerprint(['experiment', name])
        scope.set_context('experiment', payload)
        Sentry.capture_message("experiment mismatch: #{name}", level: :info)
      end
    end
  end
end
```

Fingerprinting per experiment name means one Sentry issue per experiment, with
mismatches as events under it. That is the review surface: open the issue,
read the contexts, triage (§1.5).

### 1.2 Context and cleaning

Every experiment sets context that makes a mismatch reproducible without a
customer identifier: `org_extid`, `role`, `billing_enabled`, `planid`,
`materialized_at` (membership), and `caller` (the enforcing method or route,
taken from `caller_locations(2, 1)` or passed explicitly). Never include email,
custid or raw secrets. Values under comparison are token arrays and booleans;
`clean` sorts arrays so publish output is stable.

### 1.3 Test-environment behaviour

In the test boot path set `Onetime::Experiment.raise_on_mismatches = true`
when `OT.env?(:testing)` (the normalised environment name is `testing`, not
`test`). Scientist's `included` hook extends the base class with that
class-level accessor, and the instance-level `raise_on_mismatches?` falls back
to it. The same experiment definition then fails CI on fixture data and
publishes in production. Existing entitlement tries (prep doc §7) exercise every experiment
in §2 without new fixtures.

### 1.4 Registry and removal

Experiments are temporary. Each is declared in a registry with its stage and
its removal stage; the registry is the only place an experiment can be enabled
in production.

```yaml
# etc/experiments.yaml  (loaded by Onetime::ExperimentRegistry)
ent.stage_b.feature_gate:      { enabled: true,  introduced: stage_b, remove_at: stage_c }
ent.stage_b.capability_gate:   { enabled: true,  introduced: stage_b, remove_at: stage_c }
ent.stage_b.fallback_parity:   { enabled: true,  introduced: stage_b, remove_at: stage_c }
ent.stage_c.wire_union:        { enabled: false, introduced: stage_c, remove_at: legacy_removed }
```

A tryout (`try/unit/experiments/registry_try.rb`) asserts that every
`Onetime::Experiment` subclass in the tree appears in the registry and that no
entry's `remove_at` stage has been marked complete in the same file. Marking a
stage complete without deleting its experiments fails the build. This is the
countermeasure for the most common failure with this tool: experiments that
outlive their purpose and double every read forever.

### 1.5 Mismatch triage protocol

No code changes in response to a mismatch until it carries one of four labels,
recorded in the PR that acts on it:

| Label | Meaning | Action |
|---|---|---|
| `control-wrong` | The current code returns a wrong answer at this input | Fix or accept the candidate; add the input as a fixture; do **not** make the candidate reproduce the control |
| `candidate-wrong` | The new derivation is wrong | Fix candidate; add fixture |
| `both-acceptable` | Intended behaviour change with a ruling in the prep doc | Cite the ruling (decision list row, D1/D2, L1 verdict); add to `ignore` **with the citation in the block** |
| `context-insufficient` | Cannot tell | Extend context; do not touch compare/ignore |

`ignore` and `compare` blocks are the load-bearing part of an experiment.
Any change to them in a PR must cite the mismatch it addresses. This applies
with more force when an LLM agent authors the change: an agent optimising for
a green experiment will widen `ignore` until nothing mismatches, and that
result is indistinguishable from parity unless the citations are checked.

### 1.6 Rules for agent-authored work

- Agents may add experiments and candidates freely; the control is never
  edited by an agent in the same PR that adds the experiment.
- Every mismatch an agent acts on is labelled per §1.5 with the Sentry event
  or log line cited.
- An agent does not declare parity. Parity is the registry entry's exit
  criterion (§2) being met on published data, checked by a person.
- Agents with Sentry access may pull and pre-triage mismatches; the label is
  a proposal until reviewed.

## 2. Experiments by stage

The prep doc's stages A, B and C are the anchor. Stage 0 is docs only and
Stage A adds no runtime behaviour, so the first experiments land with Stage B.

### 2.1 Stage A: coverage counter, not an experiment

Stage A introduces `PLAN_FEATURES` and `ROLE_CAPABILITIES` as derived views and
a CI assertion that they partition the merged namespace. That assertion is
static. One runtime complement is worth adding: a counter inside `can?` and
`require_entitlement!` that classifies every string actually checked in
production as `feature`, `capability` or `unknown`, with `caller`. It answers
two questions the static check cannot: which of the 23 strings are checked at
all, and whether any string outside both partitions reaches a gate (L3's
placeholder strings, or a locale-only key). It also produces the call-site
inventory the Stage B decision list needs, from traffic rather than grep.

### 2.2 Stage B: `ent.stage_b.feature_gate`

**Purpose.** Enumerate every call site where the org∩role intersection is the
only role gate on a plan feature, so the tier-preservation decision list is
derived from production rather than reading. This is the prep doc's central
risk (§8, first two bullets) and the experiment is aimed at it directly.

**Site.** Inside the Stage B `require_plan_feature!(feature)` and
`org.has_feature?` façades, which at Stage B still route to the merged set.

```ruby
def require_plan_feature!(feature)
  allowed = Onetime::Experiment.new('ent.stage_b.feature_gate').tap do |e|
    e.context(org_extid: org.extid, role: membership&.role, feature: feature,
              billing_enabled: org.billing_enabled?, caller: caller_site)
    e.use { membership.can?(feature) }                     # control: merged set, role-intersected
    e.try { org.entitlements.include?(feature.to_s) }      # candidate: Stage C answer, org plan only
    e.compare { |a, b| a == b }
  end.run
  raise EntitlementRequired.new(...) unless allowed
  true
end
```

**Reading the output.** Control `false`, candidate `true` is the interesting
case: the role intersection denied a feature the plan includes. Each distinct
`(feature, caller)` pair in that set is one row of the decision list, and it
must be ruled `preserve` (attach a capability, e.g. `manage_domains` on
`add_domain`) or `relax` before Stage C ships. Control `true`, candidate
`false` should not occur; if it does, a per-member feature grant is in play
(D2 removes those) and the grant's org needs to be listed for the Stage C
migration.

**Exit criterion.** Every `(feature, caller)` pair observed in the mismatch
set has a ruling in the decision list, and the observed `caller` population
covers every site the Stage A counter (§2.1) recorded. Remove at Stage C.

### 2.3 Stage B: `ent.stage_b.capability_gate`

**Purpose.** Measure how far §1.1 of the prep doc (capabilities stripped in
billing mode) is live in production, and confirm that the Stage C capability
derivation reproduces current authorisation everywhere it is currently
working.

**Site.** Inside `require_capability!(cap)` and `membership.has_capability?`.

```ruby
e.use { membership.can?(cap) }                                              # control: merged, intersected
e.try do                                                                    # candidate: role table only
  base = ROLE_CAPABILITIES[membership.role || 'member']   # string keys, as ROLE_ENTITLEMENTS today
  (base.to_a + membership.entitlements_grants.to_a - membership.entitlements_revokes.to_a).include?(cap.to_s)
end
```

**What the tree says today (verified at `faeca4483`, 2026-09-24).** The prep
doc's §1.1 claim that the example catalog never lists `manage_*` is stale for
the free tier. `etc/examples/billing.example.yaml` `free_v1.entitlements` lists
`manage_orgs` and `manage_org` (added in `852dbd67e8`, 2026-07-28, after the
prep doc's research); `identity_plus_v1.entitlements` lists neither. With the
example catalog deployed as is, the intersection gives a free-tier owner
`manage_org` and strips it from a paid `identity_plus_v1` owner. The
production `etc/billing.yaml` is untracked, so whether that is what runs is
unknown from the tree. Two prep-doc findings need updating in Stage 0
regardless: §1.1's citation, and H4's "can never pass when billing is enabled"
for `manage_orgs` (it is in no role set, so it still never reaches a
membership, but `org.entitlements` carries it for free orgs and the frontend
gate reads the org-level array with no role intersection).

**Reading the output.** Control `false`, candidate `true` with
`billing_enabled: true` and a paid `planid` is the §1.1 defect observed live:
the plan set did not carry `manage_*` and the intersection stripped it. Given
the catalog facts above, this is the expected signature for paid orgs and it
should be absent for free orgs. If it appears for free orgs too, production
YAML differs from the example. If it never appears for paid orgs, production
YAML carries the strings on paid plans and H6 is live in the other direction
(an operator can withhold a capability by editing YAML). Either result goes
into the Stage 0 ADR without anyone reading production config.

Control `true`, candidate `false` means a capability is currently granted by
something other than the role table plus grants: a plan listing it, or
standalone stuffing. Each such case is a row for H1/H6 cleanup.

**Exit criterion.** For memberships materialised after the Stage C backfill
formula is fixed, zero unexplained mismatches across all three roles in both
billing modes. Remove at Stage C.

### 2.4 Stage B: `ent.stage_b.fallback_parity`

**Purpose.** Close the L5 seam. `compute_entitlements_from_role` re-derives the
intersection for unmaterialised memberships but skips grants and revokes; the
prep doc judges it likely unreachable. Measure that.

**Site.** In `membership.entitlements` (the read), when
`materialized_entitlements_at` is present: candidate recomputes via
`compute_entitlements_from_role` and compares against the stored set.

```ruby
e.use { materialized_entitlements.to_a }
e.try { compute_entitlements_from_role }
e.clean { |v| v.sort }
e.run_if { entitlements_materialized? }   # existing predicate: !materialized_entitlements_at.to_s.empty?
```

**Reading the output.** A mismatch is a membership whose stored set differs
from what the fallback would compute: either an override was applied (expected
when grants/revokes are non-empty; add that to `ignore` with the citation) or
the stored set is stale relative to the org's current plan. The second case
sizes the Stage C backfill and the "no re-materialisation trigger for
`ROLE_CAPABILITIES` changes" risk (§8).

**Exit criterion.** Mismatch population fully explained by non-empty
grants/revokes or by a plan change after `materialized_entitlements_at`. Remove
at Stage C, when the backfill rewrites every membership and the fallback path
is deleted.

### 2.5 Stage C: `ent.stage_c.wire_union`

**Purpose.** During the wire back-compat window, both the legacy `entitlements`
array and the new `plan_entitlements` and `role_capabilities` fields are
emitted. The prep doc's conflict rule says the new fields win. This experiment
records every membership where they disagree, so the legacy field's removal is
gated on an empty set rather than on "we think consumers migrated".

**Site.** In the serializer that emits both (`get_permissions.rb` and
`safe_dump_fields.rb`).

```ruby
e.use { legacy_entitlements.sort }
e.try { (plan_entitlements + role_capabilities).uniq.sort }
e.ignore { |ctl, cand| decision_list.relaxed?(cand - ctl) }   # cite the ruling per token
```

**Reading the output.** `cand - ctl` non-empty is access the split added
(features flowing to all members, or capabilities no longer stripped); each
token must map to a `relax` ruling or the §1.1 fix. `ctl - cand` non-empty is
access the split removed and must map to D2 (dropped per-member feature
override) or an orphan removal (H4/H5). Anything else is `candidate-wrong`.

**Exit criterion.** Empty unexplained set over all active memberships (the
Stage C backfill iterates them; run the comparison as a batch there as well as
on the wire). Remove when the legacy array is removed.

### 2.6 Materialisation itself: batch comparison, not an experiment

The Stage C backfill (prep doc §6, "Data migration") computes
`materialized_capabilities` and `materialized_features` for every active
membership. Before it writes, it can compute both new sets and the legacy
formula for the same membership and emit the same `wire_union` comparison
offline. This gives full-population coverage in one pass, which the wire
experiment cannot (it only sees memberships that log in). Do this as a dry-run
mode of the backfill, publishing through the same `Onetime::Experiment`
publish path so triage is uniform, rather than as a `science` block around a
write.

### 2.7 Frontend: out of scope for Scientist

Scientist is Ruby. The Stage B `useFeatures` / `usePermissions` façades are
verified by the dual wire fields and the conflict rule, not by a browser-side
experiment. If a browser-side check is wanted during the back-compat window, a
dev-build-only assertion comparing `useEntitlements.can(x)` with the new
composables and reporting to the console is sufficient; do not build a
JavaScript Scientist port for it. The known divergence (M4, standalone
short-circuit) is by inspection and is fixed in Stage B, not measured.

## 3. Candidate constraints (all experiments)

- No writes. A candidate that writes, even idempotently, is rejected in
  review.
- No provider or network calls. Every candidate here reads Redis state that
  the control already loaded.
- No new Redis reads on the hot path without measuring: `feature_gate` runs
  on every gated request; its candidate reads `org.entitlements`, which the
  control already resolved, so it is free. `fallback_parity` recomputes the
  intersection, which is set arithmetic in memory. Publish durations and
  compare `cand_ms` to `control_ms` in the first day; if a candidate is more
  than 2× the control, add `run_if { rand < 0.1 }` rather than disabling.
- Exceptions in candidates are swallowed by Scientist and published with the
  class name. A candidate that raises is a mismatch for triage purposes.

## 4. What this replaces and what it does not

It replaces the manual derivation of the tier-preservation decision list
(prep doc §6 Stage B) with a measured one, and it replaces "grep `src/` for
`.entitlements` before removing the legacy field" with an empty-mismatch-set
gate. It does not replace the tryouts in prep doc §7 (those pin the
*intended* new semantics on fixtures), the CI partition assertion (static
taxonomy), or the pairing countermeasure (`require_access!` or the route
audit), which guards a class of future omission that no runtime comparison can
see.

## 5. Verification record

Checked against the working tree at `faeca4483` (2026-09-24) and the
`scientist` gem's `README.md` and `lib/scientist/experiment.rb` on `main`.

| Claim in this document | Evidence |
|---|---|
| `can?`, `entitlements`, `limit_for`, `materialize_for_role!`, `compute_entitlements_from_role` exist as pure reads | `lib/onetime/models/features/with_entitlements.rb` (`def can?`), `lib/onetime/models/organization/features/with_materialized_limits.rb` (`def limit_for`), `lib/onetime/models/organization_membership/features/with_materialized_entitlements.rb` (`def compute_entitlements_from_role`, `set :entitlements_grants`, `set :entitlements_revokes`, `field :materialized_entitlements_at`, `def entitlements_materialized?`) |
| `ROLE_ENTITLEMENTS` is keyed by role **strings** | `lib/onetime/models/organization_membership.rb`: `ROLE_ENTITLEMENTS = { 'owner' => ... }`; membership `field :role` |
| `org.billing_enabled?` is the org-level predicate | `with_plan_entitlements.rb` uses `billing_enabled?` at three sites |
| Environment name is `testing` | `lib/onetime/class_methods.rb` `def env` normalises `test`/`testing` to `'testing'`; `env?(guess)` compares against that string |
| `sentry-ruby` is available; `Sentry.with_scope` and `Sentry.capture_message` are already used | `Gemfile` L188; `lib/onetime/jobs/trace_propagation.rb`; `lib/onetime/cli/diagnostics/sentry/send_test_event_command.rb` |
| `scientist` is not yet a dependency | no match in `Gemfile` or `Gemfile.lock` |
| Scientist API used here (`include Scientist::Experiment`, `initialize(name)`, `enabled?`, `publish(result)`, `Result#matched?/mismatched?/ignored?/control/candidates`, `Observation#cleaned_value/exception/raised?/duration`, `context(hash)`, `run_if`, `ignore`, `compare`, `clean`, class-level `raise_on_mismatches=` extended onto the including class by the `included` hook, instance `raise_on_mismatches?` falling back to it) | gem README and `experiment.rb` on `main` |
| Example catalog lists `manage_org`, `manage_orgs` on `free_v1` only | `etc/examples/billing.example.yaml`, `plans.free_v1.entitlements`; introduced by `852dbd67e8` (2026-07-28) |
| Production `etc/billing.yaml` is not in the tree | `git ls-files etc/` matches only `etc/examples/billing.example.yaml` |
| `STANDALONE_ENTITLEMENTS` carries `manage_teams manage_members manage_sso manage_org manage_billing`; `FREE_TIER_ENTITLEMENTS` carries none | `with_plan_entitlements.rb` L48-70 |

Not verified: `PLAN_FEATURES`, `ROLE_CAPABILITIES`, `require_plan_feature!`,
`require_capability!`, `has_feature?`, `has_capability?`, `Onetime::Experiment`,
`Onetime::ExperimentRegistry` and `etc/experiments.yaml` do not exist yet;
they are the prep doc's Stage A/B deliverables and this document's proposals.
