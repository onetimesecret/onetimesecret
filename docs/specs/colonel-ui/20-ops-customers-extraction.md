---
labels: admin-v2, phase-1, backend
depends: 21-admin-audit-log
epic: "#3653"
---

# Admin rebuild: extract Operations::Customers::* and wire colonel + CLI through one implementation

## Context
Part of the Colonel Admin Rebuild epic. Phase-1 reference slice: prove the pattern in code by giving every customer verb exactly one implementation, shared by `bin/ots customers *` and new colonel Logic classes. Fixes the pagination debt at the source so every later list endpoint can copy the template.

## Scope
- Extract `Operations::Customers::{List, Show, SetRole, SetVerification, Purge, Doctor}` from today's inline CLI logic. Both `bin/ots customers *` and NEW colonel Logic classes delegate to them.
  - `SetVerification` already exists as `Auth::Operations::SetCustomerVerification` — **wire it through** (colonel just needs a route + button); do not rewrite it.
  - `Purge` — fold CLI's duplicate `delete_customer_keys` into the existing `Auth::Operations::DeleteCustomer`.
  - `List` — de-duplicate the CLI list vs API `list_users.rb`; **fix pagination at the source**: index-backed `ZRANGE` over `Customer.instances` / `role_index` instead of load-all-then-slice-in-Ruby. This becomes the template every later list endpoint copies.
  - `SetRole`, `Doctor` — extract from CLI-only inline logic.
- New colonel endpoints: **role change, verify/unverify, purge** (POST/DELETE). Every mutating endpoint enforces **BOTH auth layers**: `role=colonel` at the router AND `verify_one_of_roles!(colonel: true)` inside the logic; each mutation is audit-logged via the operation (see #21).
- Codify **decision D3** in `lib/onetime/operations/README.md`: app-scoped `apps/web/auth/operations/` is the incumbent home for auth/customer domain ops; cross-cutting admin verbs live central. The plan's "central lib/onetime/operations" phrasing is outdated — split = domain-owned ops app-scoped, cross-cutting admin verbs central.

## Grounding — files & pointers
- Operations contract: `lib/onetime/operations/README.md` (single `#call`, stateless, no HTTP/session, returns symbols or immutable `Data` results).
- Incumbent ops home: `apps/web/auth/operations/` — `set_customer_verification.rb`, `delete_customer.rb`, `create_customer.rb`, `close_account.rb`, `bulk_sso_migration.rb` (+ `apps/web/billing/operations/`).
- Already-shared op: `Auth::Operations::SetCustomerVerification` (`apps/web/auth/operations/set_customer_verification.rb:44`) — used by CLI `lib/onetime/cli/customers/{verify,unverify}_command.rb` + Rodauth hook `apps/web/auth/config/hooks/account.rb:298`; **no colonel endpoint calls it yet**.
- Delete duplication: `Auth::Operations::DeleteCustomer` (`apps/web/auth/operations/delete_customer.rb`) vs CLI purge's own `delete_customer_keys` (`lib/onetime/cli/customers/purge_command.rb:265,555`).
- Pagination debt: `ListUsers` (`apps/api/colonel/logic/colonel/list_users.rb:35-60`) loads ALL customers then slices in Ruby; CLI list `lib/onetime/cli/customers/list_command.rb:24-46` duplicates listing.
- CLI-only inline logic: role `lib/onetime/cli/customers/role_command.rb`; doctor `lib/onetime/cli/customers/doctor_command.rb`.
- Colonel logic base: `apps/api/colonel/logic/base.rb` extends `Onetime::Logic::Base`; ⚠️ colonel logic calls MODELS DIRECTLY today (grep for `Operations::` in `apps/api/colonel/logic` returns nothing). Colonel routes: `apps/api/colonel/routes.txt` (scope=internal, auth=sessionauth role=colonel).

## Acceptance criteria
- [ ] `Operations::Customers::{List, Show, SetRole, SetVerification, Purge, Doctor}` exist and follow the README contract (single `#call`, stateless, no HTTP/session).
- [ ] `bin/ots customers *` and the new colonel Logic classes both delegate to these ops — exactly ONE implementation per verb (CLI `delete_customer_keys` and duplicate list logic removed).
- [ ] `SetVerification` reuses existing `Auth::Operations::SetCustomerVerification` (not a rewrite); Purge reuses `Auth::Operations::DeleteCustomer`.
- [ ] List uses index-backed `ZRANGE` over `Customer.instances`/`role_index` — no load-all-then-slice.
- [ ] New colonel endpoints for role change, verify/unverify, purge exist as POST/DELETE.
- [ ] **Security invariant:** every mutating endpoint enforces BOTH `role=colonel` at the router AND `verify_one_of_roles!(colonel: true)` in the logic.
- [ ] Every mutation writes an `AdminAuditEvent` via the operation (#21).
- [ ] `lib/onetime/operations/README.md` documents the D3 app-scoped vs central split.
- [ ] Tryouts + RSpec coverage per op.

## Notes / risks
- **Extraction preserves behavior bit-for-bit**; any behavioral improvement (beyond the explicitly-scoped pagination fix) ships as a separate PR.
- Pagination fix is in-scope here specifically because it becomes the copy-template for later list endpoints — call it out in review.
- Depends on #21 so ops can write audit events at extraction time (audit is free from the start, not retrofitted).
