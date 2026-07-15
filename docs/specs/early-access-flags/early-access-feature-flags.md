# Early-Access Feature Flags — Per-Customer Opt-In to Experimental Experiences

Engineering preparation for letting individual users opt in to early features
(first target: a substantially different secret-create form experience), with
fast, layered rollback if an experiment goes wrong. Companion to — and
deliberately **not** part of — the entitlements/capabilities separation
(`docs/specs/entitlements-and-capabilities/issue-3491-plan-entitlements-vs-role-capabilities.md`).

Status: draft · Date: 2026-07-11

---

## 0. Problem statement

We want to ship experimental UX behind per-user opt-in: a user chooses to try
the new thing, everyone else sees the current thing, and any layer (the user,
an operator, a deploy) can turn it off without a migration. The system needs
to answer a question none of the existing access machinery answers: **"did
this user choose to try X?"** — user-scoped, billing-independent,
role-independent, reversible by the user themselves.

This is a *third* axis, distinct from the two that #3491 is separating:

| Question | Scope | Changes when | Owner |
|---|---|---|---|
| Does the org's subscription include X? | org | money changes | plan entitlements (#3491) |
| May this member do Y? | membership | role changes | role capabilities (#3491) |
| **Did this user opt into trying Z?** | **customer** | **user toggles it** | **this spec** |

Putting early-access strings into the entitlement namespace or billing catalog
would recreate the exact conflation #3491 §0 exists to undo — one vocabulary
answering multiple questions, with nothing recording which question a given
string answers. #3491 §0.3 already observes the space holds more than two
axes (`manage_orgs` is account-scoped); this is another one, and it gets its
own store, wire field, and read path.

## 1. Current state — four variant mechanisms, none complete for this

### 1.1 Per-customer `feature_flags` — designed at both ends, dead in the middle

The intended home exists on both sides of the stack and has never carried
traffic:

```
BACKEND                                      FRONTEND
customer.rb:99                               schemas/utils/feature_flags.ts
  hashkey :feature_flags                       featureFlagsSchema = z.record(string, boolean)
  # Per-customer feature toggles                isFeatureEnabled(flags, name)
        │                                      schemas/shapes/v3/customer.ts:51
        │                                        normalizes bool/0-1/"true" → boolean
        ▼                                        .default({})   ← silently fills the gap
customer/features/safe_dump_fields.rb              ▲
  *** feature_flags NOT LISTED ***                 │
  (objid, extid, email, role, verified,            │
   last_login, locale, counters, ...)              │
        │                                          │
        ▼                                          │
authentication_serializer.rb:28                    │
  output['cust'] = cust&.safe_dump  ──── wire ─────┘  field absent → {} → every flag false
        │
        ▼
DashboardBasic.vue:16 / DashboardEmpty.vue:20
  isBetaEnabled = computed(() => cust.value?.feature_flags?.beta ?? false)
  <RecentSecretsTable v-if="isBetaEnabled" />   ← unreachable: gate can never fire
```

Three gaps, each independently fatal:

- **No wire.** `feature_flags` is not a `safe_dump_field`
  (`lib/onetime/models/customer/features/safe_dump_fields.rb:24-47`), so the
  bootstrap payload never includes it. The Zod `.default({})` back-fills an
  empty object, so the absence is **fail-quiet**: "off" and "never delivered"
  are indistinguishable. `src/tests/fixtures/bootstrap.fixture.ts:34` includes
  `feature_flags: { beta: false }`, so contract tests exercise a payload shape
  the backend never produces — the fixture *masks* the gap rather than
  catching it.
- **No write path.** Nothing sets the hashkey: no account-settings endpoint,
  no colonel surface, no CLI. The only other reference in `lib/`/`apps/` is
  the purge command (`lib/onetime/cli/customers/purge_command.rb:52`). Today
  an opt-in means hand-editing Redis.
- **No registry.** `z.record(z.string(), z.boolean())` accepts any string.
  This is precisely the unvalidated-namespace rot #3491 §0.2 harm 3 documents
  ("nothing marks a string's kind, nothing can validate the inventory — and it
  has rotted accordingly").

The one thing this half-wiring gets *right*: absent/unknown flags resolve
false, so the default state is the stable experience. Rollback semantics are
sound by construction; observability is not.

### 1.2 Install-level `features` (bootstrap config) — the operator kill switch

`config_serializer.rb:112,164` builds `output['features']` from install
config: auth methods, organizations toggles, etc. Operator-controlled,
per-install, config-driven — the proven "turn it off for everyone without a
deploy" lever. Not per-user, and shouldn't become so; it is the **outer gate**
this spec composes with (§3.2).

### 1.3 Client-side preference: `workspaceMode` — the shipped precedent

We have already shipped an opt-in alternate secret-create experience once.
`localReceiptStore.ts:23,106,126` keeps `workspaceMode` in `localStorage`
(`onetimeWorkspaceMode`), selecting between the two-page and one-page flows
(`docs/specs/secret-creation-flows/secret-creation-flows.md`). Two lessons
carry over directly:

- The navigation branch lives in each form's `onSuccess`, not in the shared
  `useSecretConcealer` — so an alternate form mounts as a **sibling
  component**, old form untouched, and rollback is flipping the selector.
- `BrandedHomepage` hardcodes two-page (omits the prop) — custom domains are
  already excluded from variant experiences, a precedent worth keeping for
  early-access experiments (§3.4).

Its limits are why it can't be the mechanism here: per-browser not
per-account, invisible to the server, no operator override, no way to know
who's opted in.

### 1.4 Entitlements + plan preview — wrong axis, right lessons

Org-scoped, plan-driven, materialized in Redis; colonel plan-preview layered
on top (ADR-020). Not the vehicle (§0), but ADR-020's history is this spec's
strongest stability input: per-consumer opt-in polarity produced whack-a-mole
regressions ("every new consumer defaults blind"), and a dead reconciler
(`Familia.redis`) meant the feature silently never ran — hidden for months
precisely because failure looked like "off". The chokepoint decision that
fixed it (one application point all consumers inherit) is adopted wholesale
in §3.3. Note the current dashboard consumers already violate it by reaching
into the store directly.

## 2. Target design

### 2.1 Flag registry (backend constant, single source of truth)

```ruby
# lib/onetime/models/customer/features/early_access.rb (NEW)
EARLY_ACCESS_FLAGS = {
  'secret_form_v2' => {
    default: false,
    self_serve: true,          # user may toggle it themselves
    kill_switch: 'experimental.secret_form_v2', # install-config path (§2.4)
    description: 'Redesigned secret create experience',
    since: '0.xx',
    sunset: nil,               # set when the experiment graduates or dies
  },
}.freeze
```

Unknown strings are rejected at every write path and dropped at
serialization. The registry is the countermeasure to #3491-style drift: one
enumeration, machine-checkable, with a spec asserting frontend constants are
derived from it (mirror of the `entitlement_keys_spec.rb` pattern).

### 2.2 Storage — the existing hashkey, unchanged

`Customer#feature_flags` (`customer.rb:99`) stays as-is. Per-customer Redis
hash means fleet-wide revocation of a bad experiment is a scan-and-delete
script, not a migration. No org- or membership-level storage: if an
experiment must be limited to certain plans later, that is the plan-feature
axis composing with this one (§3.2), not a reason to move the flag.

### 2.3 Wire — serialize it, and make absence loud

- Add `base.safe_dump_field :feature_flags, ->(cust) { cust.early_access_flags }`
  to `customer/features/safe_dump_fields.rb`, where `early_access_flags`
  filters the raw hash through the registry (drops unknown keys, coerces
  `"true"`/`1` → boolean so the v3 shape transform's tolerance is belt-and-
  suspenders, not load-bearing). Mind the file's own note: SafeDump caches the
  field map.
- **Contract test asserts presence**: the customer payload must contain
  `feature_flags` as an object — the field being *absent* fails the contract
  suite. This converts the fail-quiet `.default({})` from a hazard into a
  convenience. Fix `bootstrap.fixture.ts` to stop pre-supplying shapes the
  backend doesn't produce.

### 2.4 Gates — three layers, operator always wins

```
effective(flag, cust) =
  install_enabled?(flag)          # config kill switch (§1.2 path), default ON for known flags
  && cust.feature_flags[flag]     # user opt-in, default OFF
```

- **Layer 1 — user**: toggles off in account settings. Needs §2.5.
- **Layer 2 — operator**: install config sets `experimental.<flag>: false`;
  ships through the existing `config_serializer` `features` path. Overrides
  every opt-in instantly, no deploy. This is the "something went terribly
  wrong" lever and it must never be buildable-around: the frontend composable
  (§2.6) ANDs it in, and the backend resolver does too, so a stale client
  can't resurrect a killed experiment.
- **Layer 3 — deploy**: because the experimental experience is a sibling
  component behind the gate (§1.3 lesson), reverting the flag's default —
  or deleting the component — touches no stable-path code.

### 2.5 Write paths

- **Self-serve** (`self_serve: true` flags): `PATCH` on account settings —
  body `{flag: 'secret_form_v2', enabled: bool}` — validated against the
  registry, authenticated-customer-scoped, no role or plan check (it is not
  an authorization question). UI: an "Early access" block in account
  settings listing registry flags with `self_serve: true` and no `sunset`.
- **Support/operator**: colonel customer screen (fits
  `docs/specs/colonel-ui/22-customers-ui.md` surface) gets a flag editor for
  any registry flag, plus a CLI (`bin/ots customers flags ...`) for scripted
  grant/revoke and the fleet-wide clear.

### 2.6 Read paths — exactly one per side (the ADR-020 rule)

- **Backend**: `Customer#early_access?(flag)` implementing §2.4. If a flagged
  experience ever needs server-side branching (API shape, new endpoint), this
  predicate is the only entry point.
- **Frontend**: `useEarlyAccess()` composable — sibling of `useEntitlements`
  — reading bootstrap `cust.feature_flags` ∧ install `features`, exposing
  `has(flag)` and typed constants derived from the registry. **No component
  reads `cust.feature_flags` directly.** `DashboardBasic.vue:16` /
  `DashboardEmpty.vue:20` migrate to it in the same PR that makes the wire
  real, so the currently-dead `beta` gate either becomes intentional (register
  `beta`) or gets deleted.

### 2.7 First consumer — secret form v2

Route/host component selects `SecretFormV2` vs `SecretForm` on
`useEarlyAccess().has(SECRET_FORM_V2)`; both forms keep their own `onSuccess`
nav branch per the flow spec's structure; `useSecretConcealer` stays shared
and routing-free. Custom domains (`BrandedHomepage`) excluded from the
experiment initially — same posture as `workspaceMode`. Interaction with
`workspaceMode` must be decided before build: v2 presumably subsumes or
ignores the one-page toggle; whichever, `localReceiptStore` remains the
source for the *stable* form's behavior, untouched.

## 3. Design rules (the ones that keep rollback trustworthy)

1. **Unknown/absent ⇒ off.** Every layer resolves missing data to the stable
   experience. Already true by accident; §2.3 makes it true on purpose and
   observable.
2. **Operator gate is ambient, not opt-in.** Both the composable and the
   backend predicate consult the kill switch; no consumer can be written that
   sees only the user bit. One chokepoint per side, period (ADR-020).
3. **Early-access strings never enter the entitlement namespace.** Not the
   billing catalog, not `ROLE_ENTITLEMENTS`, not `STANDALONE_ENTITLEMENTS`,
   not the `can?()` interface. If a flag needs plan-gating, compose:
   `org.has_feature?(x) && cust.early_access?(x)` — two axes, two predicates,
   same shape as #3491 §5.8 / the `audit_logs` dual-nature ruling (L1).
4. **Flags are temporary.** Registry entries carry `sunset`; a flag that
   graduates gets its gate removed and its entry tombstoned; a flag that dies
   gets component + entry deleted. A periodic grep-level audit (or spec) flags
   registry entries older than N releases.
5. **Experiments are additive components.** The stable code path is never
   edited to accommodate the experimental one; if it must be, that's the
   signal the change isn't flag-appropriate and needs its own migration plan.

## 4. Sequencing

Each stage ships independently; nothing blocks on, or is blocked by, #3491's
Option A/B/C stages.

**Stage 0 — make the existing wiring honest (no new features).**
Registry constant with `beta` decision (register or delete the dashboard
gate). Serialize `feature_flags` via safe_dump. Presence-asserting contract
test; fix the fixture. `useEarlyAccess()` composable; migrate the two
dashboard consumers. *Outcome: the wire is real, drift is impossible, zero
user-visible change.*

**Stage 1 — write paths.**
Self-serve settings endpoint + "Early access" settings UI. Colonel flag
editor + CLI (incl. fleet-wide clear). Install-config kill-switch path
through `config_serializer`, ANDed in both read paths. *Outcome: opt-in is
self-serve, revocation is layered, ops can act without a deploy.*

**Stage 2 — first experiment.**
`secret_form_v2` registered; v2 form as sibling component behind the
composable; custom domains excluded; `workspaceMode` interaction decided and
documented in the flow spec. *Outcome: the thing we wanted, with three
independent off-switches.*

**Stage 3 — hygiene (when warranted).**
Sunset audit. Opt-in counts on the colonel screen (a `hashkey` scan or a
counter bumped on toggle) so "how many users are on v2?" is answerable before
any graduate/kill decision.

## 5. Test impact

- New: registry validation spec (unknown-key rejection at write and dump);
  contract spec asserting `feature_flags` present on the customer payload;
  kill-switch-beats-opt-in spec at both read paths; settings endpoint
  authz spec (customer can toggle only `self_serve` flags; unknown flag 4xx).
- Changed: `bootstrap.fixture.ts:34` (stop masking); dashboard component
  specs (composable, not store reach-in);
  `customer-schema-contract.spec.ts` / v3 shape specs if the dump coerces
  values before the wire (transform tolerance becomes redundant, keep it).
- Regression to lock in: with the flag absent, on, then force-killed by
  config, the create route renders stable / v2 / stable respectively.

## 6. Risks & open questions

- **Anonymous users.** `cust` is nil for anonymous sessions; the composable
  must resolve every flag false. Fine for `secret_form_v2` on `/dashboard`,
  but the homepage `/` serves anonymous traffic — decide whether the v2
  experiment is authenticated-only at first (recommended: yes; it keeps the
  blast radius to identifiable, consenting users).
- **Bootstrap staleness.** Flags ride the bootstrap payload; a toggle takes
  effect on next bootstrap fetch. Acceptable for opt-in UX; the settings
  endpoint should return the new flag state and the store should merge it so
  the toggling session sees itself flip (same-request visibility — the small
  cousin of ADR-020's Fiber-local mirror note).
- **Kill-switch config shape.** `experimental.*` section vs a key under the
  existing `features` map — pick one; the removed-in-favor-of-`site`
  `experimental` section name is available again but has history
  (`src/schemas/contracts/config/section/site.ts:70`).
- **Per-org experiments.** If we ever want "this whole org tries v2", that is
  org-scoped state and a different store — do not overload the customer hash;
  revisit as a registry `scope:` field then, not speculatively now.
- **`beta` flag disposition.** The dashboard gate references an unregistered
  `beta` flag that has never fired in production. Registering it as-is
  changes dashboard behavior for anyone subsequently granted it — treat that
  as a product decision in Stage 0, not a mechanical carry-over.

## 7. Implementation references

- `lib/onetime/models/customer.rb:99` — `hashkey :feature_flags`
- `lib/onetime/models/customer/features/safe_dump_fields.rb:24-47` — dump list (gap)
- `apps/web/core/views/serializers/authentication_serializer.rb:28` — `cust.safe_dump` → wire
- `apps/web/core/views/serializers/config_serializer.rb:112,164` — install `features` path
- `src/schemas/utils/feature_flags.ts`, `src/schemas/shapes/v3/customer.ts:51` — FE schema + transform
- `src/apps/workspace/dashboard/DashboardBasic.vue:16`, `DashboardEmpty.vue:20,65` — dead `beta` gate
- `src/tests/fixtures/bootstrap.fixture.ts:34` — masking fixture
- `src/shared/stores/localReceiptStore.ts:23,106-126` — `workspaceMode` precedent
- `docs/specs/secret-creation-flows/secret-creation-flows.md` — form seams for the v2 host
- `docs/architecture/decision-records/adr-020-request-scoped-entitlement-preview.md` — chokepoint rule
- `docs/specs/entitlements-and-capabilities/issue-3491-...md` — axis taxonomy, drift harms, §5.8 composition
