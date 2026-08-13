---
id: 037
status: accepted
decided: 2026-08-13
title: 'ADR-037: One Boolean Token Vocabulary for Operator Flags'
---

## Context

Two parsers for operator-supplied booleans grew independently. A private
`BillingConfig#strict_bool!` accepted only `true/1/false/0` and raised on
anything else; `RABBITMQ_VERIFY_PEER` was read as `ENV.fetch(...) == 'true'`,
so `TRUE`, `1`, `yes`, or a typo silently disabled a default-ON security
control. Divergent vocabularies also contradict each other in error messages:
one parser's message advertises tokens the other rejects, and fixes to one
silently miss the other.

## Decision

One vocabulary, one parser, defined in `Onetime::Utils::Strings`:

- `TRUTHY_VALUES = %w[1 true yes on y t]`,
  `FALSEY_VALUES = %w[0 false no off n f]` — case-insensitive,
  whitespace-tolerant.
- `explicit_yes?` / `explicit_no?` are **recognizers, not a partition**:
  unrecognized input is neither yes nor no. `explicit_no?` is deliberately
  not `!explicit_yes?` — that negation would resolve a typo to "no", which
  on a default-ON control means silently off.
- `Onetime::Utils.strict_bool!(name, raw, default:)` is the sole parser for
  operator flags: blank/nil takes the caller's documented default; a
  recognized token takes its value; anything else raises
  `Onetime::ConfigError` naming the flag and the valid tokens
  ([ADR-033](adr-033-fail-fast-and-loud.md)).
- No per-caller vocabularies. A recognized synonym resolves to its value
  everywhere — never raises in one subsystem while meaning true in another.
  Strictness targets *silent misinterpretation*; rejecting `yes` was
  strictness without a safety payoff, so billing's narrow vocabulary was
  widened into the shared one rather than preserved as an exception.

## Testing policy {#testing-policy}

When a contract widens, existing testcases are preserved verbatim and new
cases are **added** for the new tokens — editing established assertions to
fit new behavior erases the record of what the contract was. The one
exception is an assertion that pins the retired contract itself (e.g.
"`BILLING_ENABLED=on` raises"): it cannot pass against the widened code and
is removed, with a comment at the site saying where the token's new
assertion lives.

## Consequences

- `BILLING_ENABLED` / `STRIPE_AUTOMATIC_TAX` now accept `yes/on/y/t` and
  `no/off/n/f`; previously these raised at boot. Widening is toward the
  operator's stated intent, not a silent flip.
- Blank remains "unset → documented default"; genuinely unrecognized tokens
  still fail the boot loudly.
- Any new flag parses via `strict_bool!` — never `== 'true'`.

## References

- `lib/onetime/utils/strings.rb` — vocabulary, recognizers, `strict_bool!`
- `spec/unit/onetime/utils/strings_spec.rb` — partition invariant
- `apps/web/billing/spec/lib/billing_config_enabled_spec.rb`,
  `billing_config_automatic_tax_spec.rb` — preserved + added coverage
