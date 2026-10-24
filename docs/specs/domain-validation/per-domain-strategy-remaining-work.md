# Per-domain validation strategy: remaining work

Status: Draft — 2026-10-22. First estimated 2026-09-18; every claim below was
re-checked against `main` on 2026-10-22. Line numbers are from that date.

Implements action row 2 of `domain-validation-policy.md` ("Add per-domain
`validation_strategy` override field, install-level value as default/fallback",
ADR-015).

## Where it stands

- ADR-015 is accepted, but none of it is implemented.
- `CustomDomain` has no `validation_strategy` field.
- `Strategy.for_config(config)` (`lib/onetime/domain_validation/strategy.rb:38`)
  takes only the global config.
- Issue #4780 (outstanding domain validation items) does not list this work.

## What the tree already covers

- All strategies share one true/false/indeterminate contract and one TXT verifier.
- `verified`, `verified_confirmed_at` and the override are independent of
  strategy, so moving a domain between strategies does not force it to be
  proven again.
- `proves_ownership?` and `bulk_rate_limit` are properties of each strategy, so
  the code does not branch on strategy names.
- Strategy aliases resolve through one table that reports the canonical name
  (`Features::STRATEGY_ALIASES`).
- The frontend goes through shared checks (`src/utils/features.ts:554-560` reads
  `domains.validation_strategy` from the bootstrap; `useDomainDnsRecord`). Only
  the source of the strategy value has to change there. The per-domain API
  payload already carries the same key under `details.cluster`
  (`features.ts:550`), so the field has a place to live.
- The TLS probe's entries in vhost are marked by source, so a fleet with mixed
  strategies cannot confuse them with Approximated's data.
- The orphaned-vhost chore (`remove_orphaned_approximated_vhosts.rb`) and the
  ACME gate (`apps/internal/acme`, `extract-rack-caddy-on-demand.md`) exist.

## What remains

1. Model and resolver (small)
   - Add the nullable field on `CustomDomain`.
   - Add `Strategy.for(custom_domain)`, which falls back to the install default.
   - Include the effective strategy in `safe_dump` and the API schemas.
2. Call sites (medium). Nine resolve the strategy from global config today:
   - `lib/onetime/operations/verify_domain.rb:185`. In bulk mode it caches one
     strategy per run, so it has to resolve per domain. Pacing then varies
     within a page.
   - `lib/onetime/operations/domains/create.rb:253`.
   - `lib/onetime/operations/domains/teardown.rb:86` (the remove path).
   - `lib/onetime/operations/domains/collision_resolution.rb:228`.
   - `lib/onetime/models/custom_domain/serving_policy.rb:151`
     (`proves_ownership?` decision).
   - `apps/api/domains/logic/domains/add_domain.rb:153`.
   - `apps/api/domains/logic/domains/get_dns_widget_token.rb:34`.
   - `apps/api/domains/cli/helpers.rb:100`.
   - The chore's `strategy_name` guard
     (`remove_orphaned_approximated_vhosts.rb:472`), which changes from "system
     strategy isn't approximated" to "this domain's strategy isn't approximated".
3. Frontend (small to medium)
   - Read the strategy from the domain record instead of the bootstrap config.
   - This affects the status badge, the DNS instructions, the DNS widget and the
     route guards.
4. ACME ask endpoint (small). Answer yes only for domains whose effective
   strategy is `caddy_on_demand`.
5. Operator tooling (medium)
   - A `bin/ots domains strategy set` command with batch support.
   - An audit record.
   - A doctor column showing each domain's effective strategy, which ADR-015
     already calls for.
   - The Colonel UI is optional.
6. Transition rules (small but needs care)
   - Decide what happens on a switch. Default: keep `verified`, reset resolving
     to unknown, and leave the vhost data for the chore.
   - Reverting must work.
7. Tests and docs. A strategy-by-call-site matrix, the mixed-page refresh path,
   and updates to ADR-015, `lib/onetime/domain_validation/README.md` and the
   changelog.
