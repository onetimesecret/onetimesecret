---
labels: authorization, organization, membership, entitlements, billing, tech-debt, issue-3491
related: "#3491, #3479, ADR-012"
status: preparation / design research
---

# Issue #3491 — Engineering Preparation: Full Separation of Plan Entitlements from Role Capabilities (Option C)

> Status: preparation / design. Read-only research consolidated from reader findings, verified taxonomy, and verified coupling audit. Code is authoritative; ADR-012 is stale (see §4). All `file:line` citations are to the shipped tree at the time of research.

> **Provenance.** This is read-only preparation research for
> [issue #3491](https://github.com/onetimesecret/onetimesecret/issues/3491). It
> consolidates a parallel codebase mapping (nine reader passes over backend
> materialization, authorization enforcement, the taxonomy source-of-truth,
> serializers/wire, frontend schemas/stores/composables, backend and frontend
> call-site inventories, docs/ADRs/tests, and #3479 history), an
> adversarially-verified entitlement taxonomy and coupling audit, and an
> independent manual re-verification of every load-bearing claim against source.
> **Code is authoritative; ADR-012 is `proposed` and stale (see §4 H7).** No
> behavior was changed in producing this document. **On `file:line` citations:**
> line numbers are best-effort snapshots taken while preparing this document and
> **will drift** as the tree changes — treat the **file path + symbol name**
> (constant, method, or comment) as the durable anchor and the line number as a
> hint. To relocate a citation, `grep` for the named symbol rather than jumping to
> the line. Where a symbol is stable, this doc prefers naming it; the numbers are
> retained only as a convenience for the tree at preparation time.


---

## 1. Executive summary

OnetimeSecret today stores two semantically different things — **plan entitlements** (what an organization's *subscription* includes: `incoming_secrets`, `custom_branding`, `audit_logs`, `custom_domains`, …) and **role capabilities** (what a member's *role* lets them do: `manage_org`, `manage_members`, `manage_sso`, `manage_billing`) — in **one undifferentiated `ENTITLEMENTS` string namespace**. Both are listed in the same billing catalog (`etc/examples/billing.example.yaml:72-163`), interleaved in the same per-role `ROLE_ENTITLEMENTS` Sets (`lib/onetime/models/organization_membership.rb:72-106`), fused into one flat `membership.materialized_entitlements` blob via the single intersection `org.entitlements ∩ ROLE_ENTITLEMENTS[role] + grants − revokes` (`lib/onetime/models/organization_membership/features/with_materialized_entitlements.rb:88-113`), checked through one concern-agnostic `can?(entitlement)` predicate (`lib/onetime/models/features/with_entitlements.rb:70-72`), and serialized to the frontend as one `org.entitlements` array consumed by one `can()` composable (`src/shared/composables/useEntitlements.ts:86-100`). The consequence: the system cannot tell *why* a check fails — a member denied `custom_branding` (a plan gap) and a member denied `manage_org` (a role gap) flow through identical code and both raise the same `EntitlementRequired` error framed as a **"upgrade your plan"** message (`lib/onetime/errors.rb:160-182`), even though no plan upgrade can ever grant a role capability. **Target end-state (Option C):** two disjoint registries and stores — `org.plan_entitlements` (subscription features, org-level, billing-driven) and `membership.role_capabilities` (role permissions, member-level, role-table-driven, billing-independent) — with two explicit check predicates (`org.has_feature?` / `membership.has_capability?`), two error/UX vocabularies ("upgrade plan" vs "insufficient role / ask an admin"), two wire fields, and two frontend composables (`useFeatures(org)` / `usePermissions(membership)`). Enforcement points that need both run **two explicit gates** (plan gate AND role gate). Limits (`secret_lifetime.max`, `role_*_per_org.max`, …) are already cleanly separated in `WithMaterializedLimits` and stay where they are.

### 1.1 The sharpest consequence — capabilities are silently stripped in billing mode

The single intersection `org.entitlements ∩ ROLE_ENTITLEMENTS[role]`
(`lib/onetime/models/organization_membership/features/with_materialized_entitlements.rb:100-101`)
treats role capabilities exactly like plan features: a capability only survives
into `membership.materialized_entitlements` **if `org.entitlements` also contains
it.** But the shipped plan catalog never lists `manage_*`: `billing.example.yaml`'s
`free_v1` and `identity_plus_v1` `entitlements:` arrays contain only plan features
(`billing.example.yaml:185-192, 227-239`). Therefore, in **billing-enabled** mode,
`org.entitlements` (= `plan.entitlements`, `with_plan_entitlements.rb:199-200`)
contains no `manage_org`/`manage_members`/`manage_sso`, and the intersection
**removes those capabilities from every membership — including the owner's.** The
only reason role authorization works today is that **standalone mode masks it**:
`STANDALONE_ENTITLEMENTS` deliberately stuffs every `manage_*` string into the org
plan set so the intersection survives (`with_plan_entitlements.rb:46-56`, comment
46-47). Concretely, `authorize_domain_config!` gates on
`require_entitlement_in!(@organization, 'manage_org')` →
`membership.can?('manage_org')` (`apps/api/domains/policies/domain_config_authorization.rb:158`,
`lib/onetime/logic/base.rb:303`), so **domain-config authorization currently depends
on `STANDALONE_ENTITLEMENTS` carrying `manage_org`** — a plan-driven set carrying a
role concern. This is latent today (paid multi-member orgs require the still-
commented-out team plan, `billing.example.yaml:274-325`) but it is the clearest
proof that the two concerns must not share the intersection: **role capabilities
must be billing-independent.**

---

## 2. Current architecture — end-to-end entitlement flow

### 2.1 Data flow (definition → materialization → check → wire → UI)

```
BILLING CATALOG / PLAN                         ROLE TEMPLATE (code)
etc/examples/billing.example.yaml:72-163       organization_membership.rb:72-106
  entitlements: {  ...plan features...         MEMBER_ENTITLEMENTS  (5)
                   manage_org, manage_sso,      ADMIN_ENTITLEMENTS   (7)  ← mixes plan+role
                   manage_members, ... }        OWNER_ENTITLEMENTS   (9)  ← mixes plan+role
  plans.<id>.entitlements: [ subset ]          ROLE_ENTITLEMENTS = owner⊇admin⊇member
        │                                                 │
        ▼                                                 │
ORG plan resolution                                       │
with_plan_entitlements.rb:177-221                         │
  !billing_enabled  → STANDALONE_ENTITLEMENTS (48-56) ◄───┘  *** pollution: STANDALONE
  materialized      → materialized_entitlements                deliberately carries
  no planid         → FREE_TIER_ENTITLEMENTS  (63-70)           manage_* so the
  plan in cache     → plan.entitlements                         intersection survives
  else              → PlanCacheMissError (fail-closed)          (comment 46-47)
        │
        ▼   org.entitlements  (ONE flat set: plan features + (standalone) role caps)
        │
        ▼  ┌─────────────────────────────────────────────────────────────┐
           │  *** THE SINGLE FUSION POINT ***                             │
           │  materialize_for_role!  (with_materialized_entitlements.rb:88-113)
           │  effective = (org.entitlements.to_set & ROLE_ENTITLEMENTS[role]).to_a   (line 100-101)
           │  apply_entitlements: plan + grants − revokes  (123-140)      │
           └─────────────────────────────────────────────────────────────┘
        │
        ▼   membership.materialized_entitlements  (ONE flat blob)
        │
        ▼   can?(entitlement) = entitlements.include?(str)
            org:        with_entitlements.rb:70-72
            membership: with_materialized_entitlements.rb:169-171
        │
   ┌────┴───────────────────────────────────────────────┐
   ▼ ENFORCEMENT (concern-agnostic, single interface)     ▼ WIRE (flat arrays)
   require_entitlement!(e)        base.rb:183-256          safe_dump_fields.rb:41  org.entitlements
   require_entitlement_in!(o,e)   base.rb:271-318          get_permissions.rb:213  membership.entitlements
     → membership.can?(e)  → EntitlementRequired           get_permissions.rb:221-241 permission booleans
   org.can?(e)  (middleware)      entitlement_check.rb:62    (mix custom_domains[plan] & manage_org[role])
        │
        ▼   FRONTEND
   useEntitlements.can(e) = org.value.entitlements?.includes(e)   useEntitlements.ts:86-100
     standalone short-circuit returns true for ALL  (88-90)
   upgradePath(e) → entitlementsStore.getRequiredPlan  → plan upgrade for ANY denial
```

### 2.2 Where plan and role merge into one namespace — exact loci

| # | Location | What merges |
|---|----------|-------------|
| 1 | `etc/examples/billing.example.yaml:113-155` | Role capabilities (`manage_org`, `manage_orgs`, `manage_teams`, `manage_billing`, `manage_members`, `manage_sso`) are defined as first-class plan **entitlement** definitions, same flat map plans reference. |
| 2 | `lib/onetime/models/organization_membership.rb:80-100` | `ADMIN_/OWNER_ENTITLEMENTS` Sets interleave plan features (`audit_logs`, `custom_domains`, `incoming_secrets`, `custom_branding`, …) with role capabilities (`manage_members`, `manage_sso`, `manage_org`, `manage_billing`). Partition is by **role**, not by concern. |
| 3 | `lib/onetime/models/organization/features/with_plan_entitlements.rb:48-56` | `STANDALONE_ENTITLEMENTS` deliberately stuffs role capabilities into the org **plan** set (comment lines 46-47) so the intersection does not drop member-level capabilities. **This is the structural reason the two cannot separate today.** |
| 4 | `lib/onetime/models/organization_membership/features/with_materialized_entitlements.rb:100-101` | The intersection `org.entitlements & ROLE_ENTITLEMENTS[role]` collapses the plan dimension and the role dimension into one `materialized_entitlements` set. After this write the two concerns are physically indistinguishable. |
| 5 | `lib/onetime/models/features/with_entitlements.rb:70-72` | One `can?(e)` predicate, mixed into both `Organization` and `OrganizationMembership`, answers both "plan includes X?" and "role permits Y?". |
| 6 | `lib/onetime/logic/base.rb:241, 303` | `require_entitlement!` / `require_entitlement_in!` take an opaque string and call `membership.can?`; a role check and a plan check have identical signatures and code paths. |
| 7 | `lib/onetime/errors.rb:160-182` | One `EntitlementRequired(entitlement, current_plan, upgrade_to)` for every denial — bakes plan-upgrade framing into role-capability denials. |

> **Note on `materialize_for_role!` doc/code drift:** the module-header `Materialization formula:` comment in membership `with_materialized_entitlements.rb` (the `= org.materialized_entitlements ∩ ROLE_ENTITLEMENTS[role]` line, near the top of the file) claims the intersection is against `org.materialized_entitlements`, but the `materialize_for_role!` method body uses `org.entitlements` (the `(org_entitlements & role_template)` line inside the method). Cited by symbol because these line numbers drift; verified drift, fix as part of any touch to this method.

---

## 3. Authoritative taxonomy table

Counts (re-verified against source at preparation; see the count-verification note below): **17 plan_feature + 6 role_capability = 23 feature/capability strings**, which matches the **23** billing-catalog `entitlements:` definitions exactly; role capabilities break down as 4 with a live role home + 2 orphaned. Plus **9 limit** keys. Backend `ROLE_ENTITLEMENTS` = 21 distinct strings (MEMBER 5 + ADMIN 7 + OWNER 9). Catalog `entitlements:` = **23** definitions. `STANDALONE_ENTITLEMENTS` = 22. `FREE_TIER_ENTITLEMENTS` = 6. Frontend `ENTITLEMENTS` runtime const = **22** keys (excludes `manage_billing`). Frontend `KNOWN_ENTITLEMENTS` = **23** (= the 22 runtime keys + `manage_billing`).

> **Count-verification note (raised in review).** An earlier draft stated Catalog = 24 and `ENTITLEMENTS` = 23; the current source has **23** catalog definitions (`etc/examples/billing.example.yaml`) and **22** `ENTITLEMENTS` keys (`src/types/organization.ts`). These totals are descriptive only — the Stage A CI assertion (§6, Appendix B) must recompute partitions from source at build time and must **not** hard-code these numbers, precisely so catalog edits can't silently invalidate them.

### 3.1 Plan features (subscription-granted, org-level)

| Entitlement | granted_by | backend role set (current) | catalog | standalone | free_tier | FE | Key source locations |
|---|---|---|---|---|---|---|---|
| `create_secrets` | plan (core) | MEMBER | ✓ | ✓ | ✓ | ✓ | yaml:73,186; membership.rb:73; wpe.rb:49,64; org.ts:48; contracts:127 |
| `view_receipt` | plan (core) | MEMBER | ✓ | ✓ | ✓ | ✓ | yaml:77,188; membership.rb:74; wpe.rb:49,65; org.ts:49; contracts:146 |
| `api_access` | plan (infra) | MEMBER | ✓ | ✓ | ✓ | ✓ | yaml:81,189; membership.rb:75; wpe.rb:49,66; org.ts:55; contracts:125 — dual-gated (org.can? middleware + membership.can?) |
| `extended_default_expiration` | plan (core) | MEMBER | ✓ | ✓ | — | ✓ | yaml:89; membership.rb:76; wpe.rb:50; org.ts:61; contracts:134 — overlaps `secret_lifetime.max` |
| `notifications` | plan (core) | MEMBER | ✓ | ✓ | — | ✓ | yaml:105; membership.rb:77; wpe.rb:49; org.ts:52; contracts:145 |
| `custom_domains` | plan (infra) | ADMIN | ✓ | ✓ | ✓ | ✓ | yaml:85,187; membership.rb:83; wpe.rb:52,67; org.ts:56; contracts:129 — **name collision** with `custom_domains.max` limit |
| `homepage_secrets` | plan (core) | ADMIN | ✓ | ✓ | ✓ | ✓ | yaml:97,191; membership.rb:84; wpe.rb:52,69; org.ts:50; contracts:136 |
| `incoming_secrets` | plan (core) | ADMIN | ✓ | ✓ | ✓ | ✓ | yaml:101,190; membership.rb:85; wpe.rb:52,68; org.ts:51; contracts:137 — **#3491 canonical plan example**; #3479 dual-gate reference |
| `custom_branding` | plan (branding) | ADMIN | ✓ | ✓ | — | ✓ | yaml:93; membership.rb:86; wpe.rb:53; org.ts:66; contracts:128 — **#3491 canonical plan example** |
| `custom_privacy_defaults` | plan (core) | ADMIN | ✓ | ✓ | — | ✓ | yaml:109; membership.rb:87; wpe.rb:53; org.ts:60; contracts:131 |
| `audit_logs` | plan (advanced) | ADMIN | ✓ | ✓ | — | ✓ | yaml:141; membership.rb:81; wpe.rb:51; org.ts:77; contracts:126 — **#3491 canonical plan example**; genuinely dual-natured (see §4) |
| `ip_access_rules` | plan (advanced) | OWNER | ✓ | ✓ | — | ✓ | yaml:137; membership.rb:91; wpe.rb:51; org.ts:57; contracts:138 — ADR puts in ADMIN (tier drift) |
| `workspace_branding` | plan (branding) | OWNER | ✓ | ✓ | — | ✓ | yaml:133; membership.rb:92; wpe.rb:51; org.ts:67; contracts:147 — ADR ADMIN (tier drift) |
| `custom_mail_sender` | plan (branding) | OWNER | ✓ | ✓ | — | ✓ | yaml:145; membership.rb:93; wpe.rb:54; org.ts:62; contracts:130 — gated via `org.can?` in sender_config/base.rb:71 |
| `flexible_from_domain` | plan (branding) | OWNER | ✓ | ✓ | — | ✓ | yaml:149; membership.rb:94; wpe.rb:54; org.ts:63; contracts:135 |
| `custom_signin_config` | plan (advanced) | OWNER | ✓ | ✓ | — | ✓ | yaml:157; membership.rb:95; wpe.rb:55; org.ts:78; contracts:132 — absent from ADR (post-ADR addition) |
| `custom_signup_validation` | plan (advanced) | OWNER | ✓ | ✓ | — | ✓ | yaml:161; membership.rb:96; wpe.rb:55; org.ts:79; contracts:133 |

### 3.2 Role capabilities (role-granted, member-level)

| Capability | granted_by | backend role set (current) | catalog | FE | Key source locations / notes |
|---|---|---|---|---|---|
| `manage_org` | role (OWNER in code; route guards treat owner∥admin) | OWNER | yaml:117 (collaboration) | ✓ | membership.rb:98; wpe.rb:55; org.ts:70; contracts:141 — **#3491 canonical**; highest-traffic role gate (update/delete org, role changes, every domain-config authorize) |
| `manage_members` | role (admin+) | ADMIN | yaml:129 (collaboration) | ✓ | membership.rb:82; wpe.rb:51; org.ts:73; contracts:140 — **#3491 canonical**; gates invitations CRUD; FE shows `upgrade_to_invite` for its denial |
| `manage_sso` | role (owner) | OWNER | yaml:153 (advanced) | ✓ | membership.rb:97; wpe.rb:55; org.ts:74; contracts:143 — **#3491 canonical**; cataloged under a *plan* category |
| `manage_billing` | role (owner) | OWNER | yaml:125 (billing) | ✗ (in KNOWN, not in ENTITLEMENTS) | membership.rb:99; wpe.rb:55; contracts:139 — **FE internal drift**: present in `KNOWN_ENTITLEMENTS` but absent from the `ENTITLEMENTS` runtime const (org.ts:46-80) |
| `manage_teams` | role (intended) | **none** | yaml:121 (collaboration) | ✓ | wpe.rb:51 (STANDALONE only); org.ts:72; contracts:144 — **ORPHANED**: in no `ROLE_ENTITLEMENTS` set, so intersection always drops it; effectively dead at membership level |
| `manage_orgs` | account-level role (intended) | **none** | yaml:113 (collaboration) | ✓ | org.ts:71; contracts:142 — **ORPHANED + account-scoped**; gates FE org-switcher/`canCreateMultipleOrgs` (OrganizationsSettings.vue:73) but never grantable when billing enabled |

### 3.3 Limits (numeric quotas — already separated, stay in `limits_plan`)

| Limit | granted_by | Key source locations / notes |
|---|---|---|
| `organizations` | plan | yaml:201 (=1); wpe.rb:115 (max=5) — **free-tier drift** (code 5 vs yaml 1) |
| `teams` | plan | wpe.rb:116 (max=0); organizationLimitsSchema.teams — tied to dormant `manage_teams` |
| `total_members_per_org` | plan | yaml:202 (=1); wpe.rb:117 (max=0) — **free-tier drift** (code 0 vs yaml 1) |
| `role_owners_per_org` | plan (quota on a role count) | yaml:203; wpe.rb:118 (max=1) — **third axis**: plan limit quantifying a role |
| `role_admins_per_org` | plan (quota on a role count) | yaml:204; wpe.rb:119 — consumed by `compute_assignable_roles` (get_permissions.rb) |
| `role_members_per_org` | plan (quota on a role count) | yaml:205; wpe.rb:120 |
| `custom_domains` (limit) | plan | yaml:206; organizationLimitsSchema; safe_dump_fields.rb — **NAME COLLISION** with `custom_domains` feature |
| `secret_lifetime` | plan | yaml:207 (14d); wpe.rb:121 (DEFAULT_FREE_TTL) — coupled to `extended_default_expiration` boolean |
| `secrets_per_day` | plan | yaml:208 (null, unimplemented) |

---

## 4. Drift & conflation inventory (ranked by severity, with decoupling action)

### HIGH

**H1 — Role capabilities live in the same namespace, catalog, and ROLE sets as plan features (the root conflation).**
`billing.example.yaml:113-155`; `organization_membership.rb:80-100`; `wpe.rb:48-56`. No type/prefix/store distinguishes "subscription includes X" from "role permits Y". `STANDALONE` (wpe.rb:46-47) explicitly requires role caps in the org plan set so the intersection survives — deliberately fusing the two at org level.
**Action:** split `ROLE_ENTITLEMENTS` into `ROLE_CAPABILITIES` (manage_* only) and remove all plan-feature strings from role Sets; remove `manage_*` from the billing catalog and any plan array; remove `manage_*` from `STANDALONE`. Plan features flow to all members (gated only by org plan); capabilities flow from the role table (no plan intersection). Model on the already-clean `has_system_role?('colonel')` axis.

**H2 — Single materialization intersection fuses the two dimensions into one blob.**
`with_materialized_entitlements.rb:88-113, 100-101, 123-140`. A member denied `custom_branding` (plan cause) and one denied `manage_org` (role cause) flow through identical code with no record of which dimension denied them. Plus the doc/code drift at lines 60-61 vs 100.
**Action:** replace the single intersection with two materialized sets — `materialized_features` (org plan features, org-scoped) and `materialized_capabilities` (`ROLE_CAPABILITIES[role]`, no plan filter), each with its own grants/revokes. Eliminate the org∩role intersection for capabilities. Fix the doc comment.

**H3 — Single `can?()` / `require_entitlement!` interface and single `EntitlementRequired` frame role denials as plan upgrades.**
`with_entitlements.rb:70-72`; `with_materialized_entitlements.rb:169-171`; `base.rb:241-256, 303-317`; `errors.rb:160-182`; `locales/content/en/api-entitlements-errors.json:52-110`; `spec/unit/onetime/locales/entitlement_keys_spec.rb:23-57`. A member denied `manage_members` gets `current_plan`/`upgrade_to` and a `<name>_required … plan upgrade` key — no plan upgrade can grant a role capability. The locale lockdown spec structurally forces plan-upgrade copy onto capability strings. FE mirrors this (`OrganizationSettings.vue` `upgrade_to_invite`).
**Action:** split predicates (`org.has_feature?` / `membership.has_capability?`); split gates (`require_plan_feature!` keeps upgrade messaging / `require_capability!` raises a new `CapabilityRequired`/role-scoped `Forbidden` with "requires `<role>` role / ask an admin" copy and **no** `current_plan`/`upgrade_to`); split locale namespaces and rewrite `entitlement_keys_spec.rb` to derive from two constants.

**H4 — `manage_orgs` has no backend role/plan home but is consumed by the frontend.**
`billing.example.yaml:113`; `org.ts:71`; `contracts:142`; absent from `membership.rb:72-106` and `wpe.rb:48-56`. Gates org-switcher (`useScopeSwitcherVisibility`) and `canCreateMultipleOrgs` (`OrganizationsSettings.vue:73`). When billing is enabled, `membership = org.entitlements ∩ ROLE[role]` can never contain it, so the gate can never pass except via the `!billing_enabled` standalone branch or the not-yet-fetched null branch.
**Action:** decide if `manage_orgs` is a real **account-level** capability (a possible third axis). Either wire it into an account-role table or remove the FE constants/gate. Do not leave a shipped FE gate keyed on a never-grantable string.

**H5 — `manage_teams` orphaned (catalog/STANDALONE/FE but no ROLE set).**
`billing.example.yaml:121`; `wpe.rb:51`; `org.ts:72`; `contracts:144`; absent from all ROLE sets. The intersection always drops it; effectively dead at membership level, yet FE renders upgrade-prompt copy. ADR-012 lists it in admin tier (ADR drift).
**Action:** classify as `role_capability` and either wire into `ROLE_CAPABILITIES` (if teams ship) or remove from STANDALONE/FE constants.

**H6 — Billing catalog defines role capabilities as first-class plan entitlements.**
`billing.example.yaml:113-155`. Operators editing billing config can grant/withhold management capabilities as if they were billing SKUs; a plan could list `manage_sso` in its `entitlements:` array.
**Action:** remove all `manage_*` from the catalog `entitlements:` and from every plan `entitlements:` array. Move capability definitions to a code-defined `ROLE_CAPABILITIES` (or a separate role-capability manifest). Optionally add `kind: plan_feature|role_capability` if the catalog must retain them for docs.

**H7 — ADR-012 normative ROLE map does not match shipped code, and is still `status: proposed`.**
`docs/architecture/decision-records/adr-012-membership-level-entitlements.md:17-92` vs `organization_membership.rb:72-106`. ADR puts `manage_teams` in admin (absent in code); several plan features ADR-OWNER vs code-ADMIN; `ip_access_rules`/`workspace_branding` ADR-ADMIN vs code-OWNER; `custom_signin_config` in code, absent from ADR. The governing document cannot be trusted as source of truth.
**Action:** treat code as ground truth; supersede ADR-012 with a new #3491 Option C ADR that declares two namespaces, two check methods, billing-independent capabilities, and reconciles every token's tier.

### MEDIUM

**M1 — Two divergent backend enforcement paths for the same string: `org.can?` (plan-only) vs `membership.can?` (plan∩role).**
`lib/middleware/entitlement_check.rb:62`; `apps/api/domains/policies/domain_config_authorization.rb:109-110,158`; `base.rb:241,303`. The middleware enforces only the plan dimension; the logic layer enforces the merged set. The domain-config policy's own comment (97-101) admits the two checks can diverge with per-member grants/revokes.
**Action:** re-express middleware as `require_plan_feature!`; make the domain-config two-gate intentional (`require_capability!('manage_org')` + `require_plan_feature!(config_entitlement)`); decide the rule for read-only endpoints.

**M2 — Domain config pages enforce role inconsistently.**
`DomainIncoming.vue:58-64` (dual gate: plan + `can(MANAGE_ORG)`) vs `DomainEmail.vue:58`, `DomainSignin.vue:62`, `DomainSignup.vue:57`, `DomainBrand.vue:71` (plan feature only, rely on route `requiresOrgRole:'admin'`). Two sources of truth (`manage_org` entitlement vs `'admin'` role string).
**Action:** convert all domain config pages to the dual-gate shape using `useFeatures(org).hasFeature(...)` AND `usePermissions(membership).can(...)`; reconcile route guards and in-component checks to one capability source.

**M3 — `manage_org` is OWNER-only in code but route guards/booleans treat it as owner∥admin.**
`membership.rb:98` (OWNER only) vs `requiresOrgRole:'admin'` (`src/router/guards.routes.ts`) and `useOrgPermissions` `canManageDomain → isOwnerOrAdmin`. An admin passes the route guard but fails an in-component `can(MANAGE_ORG)`.
**Action (DECIDED — see §8 D1):** `manage_org` stays owner-exclusive; introduce an admin+ `manage_domains` capability for the domain-config surface and repoint the domain route guards / `canManageDomain` at it. Owner-lifecycle in-component checks keep `manage_org`.

**M4 — Standalone FE `can()` short-circuits to true for ALL entitlements, including capabilities.**
`useEntitlements.ts:86-100, 88-90`. In standalone mode this grants `manage_org`/`manage_members`/`manage_sso` to any member client-side, erasing role differentiation — contradicting ADR-012's "role differentiation is preserved in self-hosted deployments." Backend still intersects with role, so FE and BE disagree.
**Action:** move the blanket-true branch into `useFeatures` only; `usePermissions(membership).can()` must honor role even in standalone.

**M5 — Permission booleans conflate both axes on the wire.**
`apps/api/account/logic/account/get_permissions.rb:221-241`. `can_view/can_edit` ← `mem.can?('custom_domains')` (plan); `can_delete/can_manage_settings` ← `mem.can?('manage_org')` (role); plus raw role-string checks and a numeric limit. Consumers can't tell which booleans are plan- vs role-bounded; `serialize_membership_for` ships `membership.entitlements` as one flat array.
**Action:** recompute booleans from two explicit predicates; ship `membership.role_capabilities` and `org.plan_entitlements` as separate typed arrays.

**M6 — `manage_billing` in FE `KNOWN_ENTITLEMENTS` but missing from FE `ENTITLEMENTS` runtime const.**
`contracts:139` vs `org.ts:46-80`. FE code cannot reference it via `ENTITLEMENTS.*`.
**Action:** add to the capability constant.

**M7 — FE constants cite a nonexistent backend file `lib/onetime/billing/catalog.rb`.**
`org.ts:41`; `contracts:122`. Real constants live in `wpe.rb:48`.
**Action:** fix the citation.

**M8 — Three enumerations of "the full set" disagree.**
`KNOWN_ENTITLEMENTS` (23) vs `STANDALONE_ENTITLEMENTS` (22) vs the billing-catalog `entitlements:` block (23). No generated source; all hand-maintained, which is exactly why the counts drifted between drafts.
**Action:** establish one generated source (or a single manifest with `kind`) and reconcile.

**M9 — `custom_domains` is both a boolean feature and a numeric limit key.**
`yaml:85` (feature) vs `yaml:206` (limit); `membership.rb:83` vs `organizationLimitsSchema`.
**Action:** disambiguate — keep the feature flag as "may use custom domains at all", keep `custom_domains.max` as "how many"; rename one to avoid the collision.

**M10 — `free_tier_limits` (code) disagree with `billing.yaml` `free_v1`.**
`wpe.rb:115-122` (organizations=5, total_members=0) vs `yaml:201-202` (organizations=1, total_members=1). Effective caps depend on which path materialized the org.
**Action:** reconcile the two free-tier limit sources.

**M11 — Billing webhook recomputes role-capability sets on a plan event.**
`apps/web/billing/operations/apply_subscription_to_org.rb:195-229`; `organization.rb:315-339`. Because `membership = org.entitlements ∩ ROLE[role]`, a plan change re-derives every member's capability set even though capabilities never change on a plan event.
**Action:** after separation, the webhook re-materializes only plan features; `change_role!` (`membership.rb:258-274`) becomes the sole driver of capability re-materialization. Add a separate trigger for `ROLE_CAPABILITIES` table changes.

**M12 — Wire `check_entitlement` / billing `#check` returns upgrade framing for ANY string.**
`safe_dump_fields.rb:41`; `apps/web/billing/controllers/entitlements.rb`; `wpe.rb:248-262`. Asking about `manage_org` yields a billing upgrade suggestion.
**Action:** restrict `check_entitlement`/billing `#check` to plan features; reject/differently-handle capability strings.

### LOW

**L1 — `audit_logs` and `api_access` are genuinely dual-natured.** Whether the org *has* the feature is a plan question; whether a role may *view/use* it is a capability question — collapsed to one string. (`membership.rb:81,75`; `entitlement_check.rb:62`; `base.rb`.) **Action:** per-token product decision — each may need to exist in both registries (plan availability + role permission). **Recommended default pattern** (for turning this into tickets): keep a plan-feature flag for "the org has purchased X" (org-scoped, billing gate) *and* add a distinct role-capability for "this role may access/use X" (member-scoped, role gate); the gate then reads `org.has_feature?(:audit_logs) && membership.has_capability?(:view_audit_logs)`. Only split tokens where both questions are real — do not mint a capability for features every member may use once the org has them (e.g. `create_secrets`).

**L2 — `extended_default_expiration` boolean duplicates `secret_lifetime.max`.** `membership.rb:76`; `wpe.rb:121`; `apps/api/v2/logic/secrets/base_secret_action.rb:122-123`. **Action:** convert to the numeric limit; drop the boolean stand-in.

**L3 — `priority_support` / `basic_sharing` / `create_team(s)` appear in plan lists or FE docs but have no ROLE/STANDALONE home.** `ENTITLEMENT_QUICK_REFERENCE.md`; `entitlement_enforcement_spec.rb`. **Action:** treat as plan-only or remove placeholder/example strings.

**L4 — Operator overrides target one namespace on both layers.** `apps/api/colonel/logic/colonel/manage_entitlement_override.rb`; `with_materialized_entitlements.rb:173-204`. An operator can grant `manage_org` (role) or `incoming_secrets` (plan) through the identical path. **Action (per §8 D2):** restrict org-level overrides to plan features and membership-level overrides to **capabilities only** — drop per-member *feature* overrides entirely rather than porting them; migrate existing override data.

---

## 5. Target design (Option C)

### 5.1 Two registries (backend constants)

Split `Onetime::OrganizationMembership::ROLE_ENTITLEMENTS` (`organization_membership.rb:72-106`) into **`ROLE_CAPABILITIES`** (capabilities only) and remove plan features from role templates entirely. Define **`PLAN_FEATURES`** as the canonical plan-feature registry (or keep it billing-driven and derive a frozen allow-list).

```ruby
# lib/onetime/models/organization_membership.rb  (NEW shape)
MEMBER_CAPABILITIES = Set[].freeze                     # members: no management caps
ADMIN_CAPABILITIES  = Set['manage_members', 'manage_domains'].freeze  # manage_domains: ratified admin+ cap for the domain-config surface (see §8 D1)
OWNER_CAPABILITIES  = Set['manage_org', 'manage_sso', 'manage_billing'].freeze  # manage_org stays owner-exclusive (D1); + manage_teams if shipped
# NOTE: OWNER_CAPABILITIES holds only owner-EXCLUSIVE caps. Owners inherit
# manage_members transitively via the ROLE_CAPABILITIES union below (owner ⊇
# admin ⊇ member), so it is intentionally NOT re-listed here.
ROLE_CAPABILITIES = {
  owner:  OWNER_CAPABILITIES | ADMIN_CAPABILITIES | MEMBER_CAPABILITIES,
  admin:  ADMIN_CAPABILITIES | MEMBER_CAPABILITIES,
  member: MEMBER_CAPABILITIES,
}.freeze
# NO plan features here. Plan features are NOT role-gated.
```

```ruby
# lib/onetime/models/organization/features/with_plan_features.rb  (renamed from with_plan_entitlements)
PLAN_FEATURES = Set[
  'create_secrets','view_receipt','api_access','extended_default_expiration','notifications',
  'custom_domains','homepage_secrets','incoming_secrets','custom_branding','custom_privacy_defaults',
  'audit_logs','ip_access_rules','workspace_branding','custom_mail_sender','flexible_from_domain',
  'custom_signin_config','custom_signup_validation'
].freeze
STANDALONE_FEATURES = PLAN_FEATURES   # NO manage_* — capabilities now come from the role table, billing-independent
FREE_TIER_FEATURES  = Set['create_secrets','view_receipt','api_access','custom_domains','homepage_secrets','incoming_secrets'].freeze
```

**`billing.example.yaml`:** remove `manage_orgs`, `manage_org`, `manage_teams`, `manage_billing`, `manage_members`, `manage_sso` from `entitlements:` (lines 113-155) and from every plan's `entitlements:` array. The catalog becomes plan-features + limits only. Role-count limits (`role_*_per_org`) remain in `limits:` (they are plan limits ON roles, the third axis).

### 5.2 New model fields / Redis sets

| Object | Field (current) | Field (target) |
|---|---|---|
| Organization | `set :entitlements_plan`, `set :materialized_entitlements`, grants/revokes (`with_materialized_entitlements.rb:66-86`) | unchanged in shape but **plan-features-only**; never write `manage_*` here |
| Organization | — | (limits unchanged: `hashkey :limits_plan`) |
| OrganizationMembership | `set :entitlements_plan`, `set :materialized_entitlements`, grants/revokes (`with_materialized_entitlements.rb:53-64`) | `set :materialized_features` (= org plan features, org-scoped read-through) **+** `set :materialized_capabilities` (= `ROLE_CAPABILITIES[role]`), each with own grants/revokes |

Materialization becomes two independent paths (no intersection):

```ruby
# membership materialize (target)
def materialize_capabilities!
  effective = ROLE_CAPABILITIES[role || 'member'].dup        # role table only; NO plan intersection
  apply_capabilities(effective)                              # + capability grants − revokes
end
# plan features are read at org level; membership exposes them read-through for the wire only.
```

### 5.3 New check interface (two predicates, two gates)

```ruby
# org-level
org.has_feature?(:custom_branding)        # reads PLAN_FEATURES via org plan resolution
# membership-level
membership.has_capability?(:manage_members)  # reads ROLE_CAPABILITIES[role] (+grants−revokes)

# logic gates
require_plan_feature!('incoming_secrets')   # → org dimension; raises EntitlementRequired (upgrade messaging OK)
require_capability!('manage_org')           # → role dimension; raises CapabilityRequired (NO upgrade fields)
```

Deprecate the generic `can?()` / `require_entitlement!` once call sites are re-typed.

### 5.4 New serializer wire fields

- `org.plan_entitlements: string[]` (subscription features only) — replaces/renames `safe_dump` `org.entitlements` (`safe_dump_fields.rb:41`) and billing `#show` (`entitlements.rb:50`).
- `membership.role_capabilities: string[]` (role permissions only) — replaces `membership.entitlements` (`get_permissions.rb:213`).
- Catalog endpoints (`get_entitlements.rb` / billing `#list`) add a `kind: 'plan_feature'|'role_capability'|'limit'` discriminator per definition so the FE renders upgrade UI vs role-assignment UI without inferring from `category`.
- Frontend Zod (`src/schemas/contracts/bootstrap.ts:396-405`, permissions/billing schemas) add `org.plan_entitlements` and `membership.role_capabilities` as distinct typed arrays.

### 5.5 New frontend types / composables

- Split `ENTITLEMENTS` (`src/types/organization.ts:46-80`) into `PLAN_FEATURES` and `ROLE_CAPABILITIES` constants + `planFeatureSchema`/`roleCapabilitySchema` (replace bare `z.string()` in `contracts/organization.ts`). Add `MANAGE_BILLING` to the capability constant. Fix the stale `lib/onetime/billing/catalog.rb` citation (org.ts:41, contracts:122).
- `useFeatures(org).hasFeature(feature)` — reads `org.plan_entitlements`, owns `upgradePath`/`getRequiredPlan`, **may** short-circuit `true` in standalone.
- `usePermissions(membership).can(capability)` — reads `membership.role_capabilities`, **no** upgrade mapping, **must** honor role in standalone. Converges with today's `useOrgPermissions`/`useResourcePermissions`.

### 5.6 Before/after — endpoint (domain config authorize)

**Before** (`apps/api/domains/policies/domain_config_authorization.rb:109-110,158`; comment admits divergence):
```ruby
require_entitlement_in!(@organization, 'manage_org')           # role gate via membership.can?
# ... later ...
organization.can?(config_entitlement)                          # plan gate via org.can?  (divergent path)
```
**After:**
```ruby
require_capability!('manage_org')                              # explicit role gate → CapabilityRequired
require_plan_feature!(config_entitlement)                      # explicit plan gate → EntitlementRequired (upgrade)
```
Both gates intentional, principled, same error semantics across middleware and logic layers.

### 5.7 Before/after — Vue component (`DomainEmail.vue`, currently plan-only)

**Before** (`src/apps/workspace/domains/DomainEmail.vue:58`; relies on route `requiresOrgRole:'admin'`):
```ts
const hasEntitlement = computed(() => can(ENTITLEMENTS.CUSTOM_MAIL_SENDER))   // plan only
// v-else-if="!hasEntitlement" → form  (no in-component role gate)
```
**After** (matches the #3479 reference shape from `DomainIncoming.vue:58-64`):
```ts
const hasMailFeature   = computed(() => useFeatures(org).hasFeature(PLAN_FEATURES.CUSTOM_MAIL_SENDER)) // plan → upgrade branch
const canManageOrg     = computed(() => usePermissions(membership).can(ROLE_CAPABILITIES.MANAGE_ORG))   // role → access-denied branch
const canConfigure     = computed(() => hasMailFeature.value && canManageOrg.value)
// template: !hasMailFeature → "upgrade plan"; hasMailFeature && !canManageOrg → "insufficient permissions"; else → form
```

### 5.8 Feature ↔ capability relationship (two composing axes, not a hierarchy)

The two registries are **orthogonal axes that compose at a gate**, not a tree of
capabilities nested under features. The relationship between them is many-valued
in one direction and partial in both:

- **One plan feature → 1..N role capabilities.** A feature answers "is this
  available at all"; the capabilities answer "which role may *view / use /
  manage* it." This is already latent in the code: the `custom_domains` feature
  yields `can_view`/`can_edit` for any member but `can_delete`/`can_manage_settings`
  only with `manage_org` (`apps/api/account/logic/account/get_permissions.rb:221-241`).
  After separation this becomes explicit: a gate reads
  `org.has_feature?(:custom_domains)` **AND** `membership.has_capability?(:manage_domain)`.
- **Not total in either direction.** Some capabilities have **no owning feature**
  — `manage_members`, `manage_org` are pure role concerns, gated by role alone
  regardless of plan. Some features need **no capability split** — a boolean
  like `notifications` is fully answered by the plan axis. So do not force every
  capability under a feature (or vice-versa); model them as two independent
  registries whose gates `AND` together only where both apply.
- **Design consequence.** `require_plan_feature!` and `require_capability!` stay
  separate calls; a two-gate endpoint invokes both (§5.6). The "feature owns
  capabilities" intuition is a useful *documentation* grouping (which verbs a
  feature exposes) but must **not** be encoded as storage nesting — that would
  reintroduce the coupling this refactor removes.

---

## 6. Migration & sequencing plan

Ordered, low-risk. Each stage ships independently and is backward-compatible with materialized Redis sets and the wire contract until the final cutover.

**Stage 0 — establish ground truth (docs only, no code).**
Supersede ADR-012 with a new #3491 Option C ADR. Reconcile the ADR-vs-code tier drift (H7), document `manage_teams`/`manage_orgs` orphan status (H4/H5), document the `audit_logs`/`api_access` dual-nature decision (L1), the `custom_domains` feature/limit collision (M9), and the free-tier limit drift (M10). Fix stale FE citations (M7) and `materialize_for_role!` doc comment (H2 note). No behavior change.

**Stage A — Option A: naming + classification (additive, no behavior change).**
Introduce `kind` metadata: add `PLAN_FEATURES`/`ROLE_CAPABILITIES` Ruby constants and the FE `planFeatureSchema`/`roleCapabilitySchema` as **derived views** over the existing single namespace (no storage change yet). Add the `kind` discriminator to the catalog endpoints. Add `manage_billing` to the FE capability constant (M6). Reconcile the three enumerations into one manifest (M8). This makes the taxonomy machine-readable while `can?()` still works unchanged.

**Stage B — Option B: dual interfaces (parallel, backward-compatible).**
Add `org.has_feature?` / `membership.has_capability?` and `require_plan_feature!` / `require_capability!` that, in this stage, route to the existing merged set (so behavior is identical) but carry the correct **error semantics** (capability denials raise `CapabilityRequired` with no `current_plan`/`upgrade_to`; split locale keys — H3). Add wire fields `org.plan_entitlements` and `membership.role_capabilities` **alongside** the legacy `entitlements` arrays (do not remove yet). Add FE `useFeatures`/`usePermissions` as façades over the current `org.entitlements`. Convert domain config pages to the dual-gate shape (M2) and fix the standalone short-circuit to apply only to features (M4). Re-type call sites (`update_member_role.rb`, invitations → `require_capability!`; `add_domain.rb`, domain features → `require_plan_feature!`). At this point the two interfaces exist and produce correct UX, but storage is still merged.

**Stage C — full separation (storage cutover).**
Split materialization into `materialized_features` and `materialized_capabilities`; remove the org∩role intersection for capabilities (H1/H2); remove `manage_*` from `STANDALONE` and the billing catalog (H1/H6); make capabilities billing-independent. Decouple the webhook so plan events no longer recompute capabilities (M11); `change_role!` becomes the sole capability driver. Split operator overrides and **remove the per-member feature-override path** (L4, §8 D2); membership overrides become capability-only. Restrict `check_entitlement`/billing `#check` to features (M12). Remove the legacy merged `can?()`/`require_entitlement!` and the legacy wire arrays after a deprecation window.

**Backward-compat for materialized Redis sets.** Keep the legacy `materialized_entitlements` set written (mirrored from features+capabilities) through Stages B and C until all readers move to the two new sets; a flag (e.g. `materialized_entitlements_at`'s content hash, `with_materialized_entitlements.rb:46-57`) detects staleness for re-materialization.

**Backward-compat for the wire contract.** Ship `plan_entitlements` + `role_capabilities` alongside the legacy `entitlements` array for at least one release; FE reads the new fields when present, falls back to the legacy array. **Conflict rule (partial deploy):** when both the new fields and the legacy `entitlements` array are present and disagree (e.g. a partially-rolled-out backend), the **new fields are authoritative and the legacy array is ignored** — never union or intersect the two. FE presence-checks the new fields first and only reads the legacy array when the new fields are entirely absent. Remove the legacy field only after FE consumers are confirmed migrated (grep `src/` stores for `.entitlements` on membership/permissions payloads first).

**Data migration for already-materialized memberships.** A one-shot backfill (model on `materialize_standalone_entitlements` / `ensure_member_through_models` chores, `organization.rb:315-339`) iterates active memberships and writes `materialized_capabilities = ROLE_CAPABILITIES[role] + capability_grants − capability_revokes` and `materialized_features` from the org plan set, idempotently, with targeted retry. Because capabilities are now derived purely from role, the backfill is deterministic and re-runnable; legacy `materialized_entitlements` is left intact until the wire/readers cut over.

---

## 7. Test impact — specs/tries that lock in the single-namespace contract

These assert the merged model and **must change** under Option C:

- `try/unit/models/organization_membership_entitlements_try.rb:36-214` — pins the `ROLE_ENTITLEMENTS` hierarchy and that a member `can?('api_access')` and an owner `can?('manage_billing')` via the same `can?`; operator grant of `manage_members` to a member. Split into plan-vs-capability calls.
- `spec/unit/onetime/models/organization_membership/with_materialized_entitlements_spec.rb:29-310` — asserts `ROLE_ENTITLEMENTS` structure (admin includes `custom_domains` AND `manage_members` at 77-85) and one materialized set checked by one `can?`. Move feature assertions to the plan layer; capability assertions target the capability interface.
- `spec/unit/onetime/locales/entitlement_keys_spec.rb:23-57` + `locales/content/en/api-entitlements-errors.json:52-110` — forces a `<name>_required … plan upgrade` key for every `STANDALONE` entry incl. capabilities. **The concrete change is the spec's derivation source:** today it iterates `STANDALONE_ENTITLEMENTS` and asserts one plan-upgrade key per string; after separation it must iterate **two** constants — `PLAN_FEATURES` (asserting `_required` upgrade keys) and `ROLE_CAPABILITIES` (asserting the new "insufficient role / ask an admin" vocabulary) — which operationalizes the §6 Stage B "split locale namespaces" step. Not a copy tweak: the loop's source-of-truth constant changes.
- `spec/api/account/get_permissions_spec.rb:254-358, 557-576` — encodes "member lacks `custom_domains` → cannot view domain" (a plan feature gating a per-member capability through one `can?`). Recompute from two predicates `(org has feature) AND (role permits)`.
- `try/integration/api/colonel/manage_entitlement_override_try.rb:122-244` — operator grant/revoke treats every string uniformly via one effective-entitlements list. Needs a feature-vs-capability target or split endpoints.
- `with_plan_entitlements_standalone_spec.rb` / `organization_entitlements_try.rb` — drop capability strings from the standalone/plan set once capabilities are role-derived.
- `change_role_spec.rb` — asserts re-materialization on role change; update to drive `materialized_capabilities` only.
- `entitlement_enforcement_spec.rb` — `org.can?('api_access')` plan gating; re-type to `require_plan_feature!` and decide the `api_access` dual-nature ruling (L1).

New tests required: `require_capability!` raises `CapabilityRequired` (no upgrade fields); standalone preserves role differentiation for capabilities; webhook does **not** recompute capabilities; backfill idempotency.

---

## 8. Risks & open questions

- **Dual-natured tokens (`audit_logs`, `api_access`).** Product decision required: does each need to exist in **both** a plan-feature registry (availability) and a capability registry (who may view/use)? (L1) This is not a mechanical split.
- **`manage_orgs` as a third axis.** It is account-scoped ("manage organizations on your account"), not org-scoped. Option C may need an **account-role** dimension distinct from both org-plan and org-role. (H4)
- **DECIDED (D1) — `manage_org` stays owner-exclusive; add an admin+ `manage_domains` capability.** Code makes `manage_org` OWNER-only while route guards/`useOrgPermissions` already admit owner∥admin, so admins pass route guards but would fail `can(MANAGE_ORG)` (M3). Ratified resolution: keep `manage_org` **owner-exclusive** for org-lifecycle actions (rename, delete, billing, SSO) and introduce a distinct **admin+ `manage_domains`** capability for the domain-config surface admins already reach — aligning the model with shipped route-guard behavior instead of widening `manage_org`. Reflected in §5.1 (`ADMIN_CAPABILITIES` now includes `manage_domains`) and M3.
- **DECIDED (D2) — per-member *feature* overrides are unsupported; per-member *capability* overrides stay.** ADR-012 routed feature checks through membership so a per-member revoke could disable a feature for one user. Ratified resolution: **drop** per-member feature overrides (features are a property of the org's subscription, not the member) and **keep** per-member capability overrides (the colonel grant/revoke path, inherently member-scoped). No current spec/CLI exercises a per-member feature revoke, so Stage C removes that path and L4 splits overrides accordingly.
- **RESOLVED — `/billing/entitlements/:extid` returns org-level plan entitlements, not the role-intersected set.** `Billing::Controllers::Entitlements#show` returns `entitlements: org.entitlements_for_request(session)` (org plan entitlements + colonel preview overrides), **not** any membership set. So the frontend's `org.entitlements` is genuinely org-level plan data with **no role filter** — the schema's "org-level" framing is correct, and the fix is a **re-label** (`org.entitlements` → `org.plan_entitlements`) plus a **new membership/permissions field** for `role_capabilities`, not a re-scope of the existing endpoint. (Verified in `apps/web/billing/controllers/entitlements.rb#show`.)
- **Standalone capability grant path.** Today `STANDALONE` carries capabilities so the intersection survives. After separation, what grants capabilities in self-hosted mode — every member gets all, or role is honored (per ADR-012's claim)? Must be honored to fix M4.
- **`extended_default_expiration` → limit conversion** (L2) changes the gate at `base_secret_action.rb:122-123` and `update_domain_brand.rb`; verify no behavior regression around the free TTL ceiling.
- **No re-materialization trigger exists for `ROLE_CAPABILITIES` table changes** (a code constant). A deploy that changes the table must trigger a backfill; today only webhooks/role-changes re-materialize.
- **Free-tier limit drift (M10)** means effective caps depend on which path materialized an org; reconcile before relying on either source in tests.

---

## 9. Acceptance-criteria mapping

| Issue #3491 acceptance criterion | Where addressed in this prep doc | Concrete deliverable |
|---|---|---|
| Plan entitlements and role capabilities are clearly distinguished | §3 taxonomy; §5.1 two registries | `PLAN_FEATURES` vs `ROLE_CAPABILITIES`; remove `manage_*` from catalog/STANDALONE/role Sets (H1, H6) |
| Separation reflected in storage / data model | §5.2; §6 Stage C | `org` plan-features-only; `membership.materialized_features` + `materialized_capabilities`; eliminate the org∩role intersection (H2) |
| Separation reflected in the check interface | §5.3 | `org.has_feature?` / `membership.has_capability?`; `require_plan_feature!` / `require_capability!`; deprecate `can?()`/`require_entitlement!` (H3) |
| Role denials are not framed as plan upgrades | §4 H3; §5.3; §6 Stage B; §7 | `CapabilityRequired` (no `current_plan`/`upgrade_to`); split locale namespaces; rewrite `entitlement_keys_spec.rb`; fix `upgrade_to_invite` UX |
| Separation reflected on the wire | §5.4; §6 (dual-field back-compat) | `org.plan_entitlements` + `membership.role_capabilities`; `kind` discriminator on catalog endpoints |
| Separation reflected in the frontend | §5.5, §5.7; §4 M2/M4/M6/M7 | `useFeatures(org)` / `usePermissions(membership)`; split `ENTITLEMENTS` const; dual-gate all domain config pages; fix standalone short-circuit |
| Consistent enforcement across paths | §4 M1; §5.6 | Re-express middleware and domain-config policy in the two-dimension API; remove accidental divergence |
| Billing lifecycle decoupled from authorization | §4 M11; §6 Stage C | Webhook re-materializes features only; `change_role!` is the sole capability driver |
| Migration is low-risk and backward-compatible | §6 | Option A → B → C sequencing; Redis-set + wire back-compat; idempotent membership backfill |
| Documentation/contract is trustworthy and current | §4 H7; §6 Stage 0 | Supersede ADR-012; reconcile tier drift; fix stale citations; one generated manifest |
| Orphans resolved | §4 H4/H5; §3.2 | Wire or remove `manage_teams` and `manage_orgs` (decide account-role axis) |
| Limits remain correctly attributed | §3.3; §1 | Limits stay in `WithMaterializedLimits`; `role_*_per_org` documented as plan limits ON roles (third axis); reconcile free-tier drift (M10) |

---

## 10. Forward compatibility — object-level (per-resource) permissions

Separation is the **prerequisite** for object-level permissions, not a detour
from them. Once role capabilities are their own billing-independent axis, the
capability check is a `(subject, verb)` pair — `membership.has_capability?(:manage_org)`
— which extends naturally to a `(subject, verb, object)` triple:
`membership.has_capability?(:manage_domain, on: domain)`. The **plan-feature axis
stays org-wide** (a subscription is never scoped per object); only the
**capability axis** gains object granularity. This is the RBAC → object-scoped
(ReBAC/ABAC) path.

The groundwork already exists and should be treated as the seam to build on:

- **`domain_scope_id` / `can_access_domain?`** (`lib/onetime/models/organization_membership.rb:280-290`)
  is effectively a first object-level capability gate today — a membership whose
  access is restricted to one domain. Generalize this from a single scope field
  to a `(capability, object)` grant.
- **Per-membership `entitlements_grants` / `entitlements_revokes`**
  (`with_materialized_entitlements.rb:173-204`) are already per-subject overrides.
  Extending the stored key from `capability` to `capability@object` yields
  per-resource grants/revokes with no new machinery.
- **`require_capability!(cap)`** evolves to `require_capability!(cap, on: object)`;
  callers with no object argument default to the org scope (backward-compatible).

Why keeping the two fused would block this: a plan feature **cannot** be
sensibly scoped to an object (you don't buy `incoming_secrets` per domain), so an
object dimension only makes sense on the capability axis. As long as both live in
one namespace and one `can?()`, there is nowhere to attach the object without it
leaking into the plan concern. Separating first gives object-level permissions a
clean axis to hang from. **Non-goal for this issue** — listed only so Stage C's
storage shape (per-capability grants/revokes, no plan intersection) is chosen to
not foreclose it.

---

## Appendix A — Independently re-verified claims

Every claim below was confirmed by reading the cited source directly during
preparation (not only via the reader passes):

| Claim | Source confirmed |
|---|---|
| One flat namespace mixes plan features and role capabilities | `etc/examples/billing.example.yaml:72-163`; `lib/onetime/models/organization_membership.rb:72-106`; `src/types/organization.ts:46-80` |
| Membership = `org.entitlements ∩ ROLE_ENTITLEMENTS[role] + grants − revokes` | `lib/onetime/models/organization_membership/features/with_materialized_entitlements.rb:88-140` |
| Plans never enumerate `manage_*` → intersection strips capabilities in billing mode | `etc/examples/billing.example.yaml:185-239`; `with_plan_entitlements.rb:177-221` |
| `STANDALONE_ENTITLEMENTS` deliberately carries `manage_*` to keep the intersection from dropping them | `with_plan_entitlements.rb:46-56` |
| Two divergent enforcement paths: `membership.can?` vs `org.can?` | `lib/onetime/logic/base.rb:241,303`; `lib/middleware/entitlement_check.rb:62` |
| The one explicit two-gate site admits its two paths "can diverge" | `apps/api/domains/policies/domain_config_authorization.rb:88-101,158-159` |
| Permission booleans conflate plan and role axes on the wire | `apps/api/account/logic/account/get_permissions.rb:213,221-241` |
| Bootstrap ships `planid` + `current_user_role` but **not** entitlements; `org.entitlements` loads from `/billing/api/entitlements/:extid` | `apps/web/core/views/serializers/organization_serializer.rb:55-73`; `src/shared/stores/organizationStore.ts:299-341` |
| Frontend `can()` reads `org.entitlements` with **no role intersection**; standalone short-circuits `true` for everyone, although `current_user_role` is available | `src/shared/composables/useEntitlements.ts:86-100`; bootstrap org payload |
| ADR-012 role tiers do not match shipped `ROLE_ENTITLEMENTS` | `docs/architecture/decision-records/adr-012-membership-level-entitlements.md:31-48` vs `organization_membership.rb:72-106` |

## Appendix B — Where to start (smallest first PR)

Stage 0 (docs) + the highest-signal, lowest-risk slice of Stage A:

1. Land this document and supersede ADR-012's status note (point to #3491).
2. Add backend `ROLE_CAPABILITIES` and `PLAN_FEATURES` constants as **derived
   views** over today's sets (no storage/behavior change) and a CI assertion that
   the two partitions are disjoint and exhaustive over `ROLE_ENTITLEMENTS ∪
   STANDALONE_ENTITLEMENTS` — this freezes the taxonomy and prevents new drift.
3. Fix the two free, unambiguous drifts: the stale `lib/onetime/billing/catalog.rb`
   citation (present in **both** `src/types/organization.ts` near the `ENTITLEMENTS`
   const header and `src/schemas/contracts/organization.ts` above `KNOWN_ENTITLEMENTS`)
   and the `materialize_for_role!` doc/code comment mismatch (the module-header
   `Materialization formula:` comment says `org.materialized_entitlements` but the
   method body uses `org.entitlements` — see the §2.2 note).
4. Add `manage_billing` to the frontend capability constant (M6).

None of these change runtime behavior; together they make the taxonomy
machine-checked so Stages B and C can proceed without regressions.
