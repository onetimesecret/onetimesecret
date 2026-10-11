# Domain Permissions for Secret Creation

Behavioral specification for `validate_domain_permissions` authorization logic.

## Overview

Three tables define the permission matrix. The first establishes the generic rules;
the endpoint-specific tables show which cells are reachable given each endpoint's
auth strategy.

## Generic `validate_domain_permissions` Rules

| Caller | Domain context | Toggle | Result |
|---|---|---|---|
| Owner / org member | any | any | ✓ allowed |
| Authenticated non-owner | custom | on | 403 "You do not have permission" |
| Authenticated non-owner | custom | off | 403 "You do not have permission" |
| Authenticated non-owner | canonical | n/a | 403 "You do not have permission" |
| Anonymous | custom | on | ✓ allowed (public intake) |
| Anonymous | custom | off | 403 "Public sharing disabled" |
| Anonymous | canonical (with share_domain) | n/a | 403 "You do not have permission" |

**Toggle semantics:** "on" means `CustomDomain#allow_public_secret_creation?` —
the homepage is enabled **and** its `secrets_mode` is `create` **and** the
caller's network is admitted by the homepage's network rules. A homepage in
`incoming` mode is public but presents the incoming-secrets form instead; it
does **not** authorize anonymous secret creation (those visitors submit via
`POST /api/incoming/secret`, which has its own gating), so anonymous creation
on an incoming-mode domain returns 403 "Public sharing disabled".

**Network rules:** `HomepageConfig#allowed_cidrs` / `#denied_cidrs` narrow the
"on" cell per visitor. Both lists empty (the default) means no restriction. A
caller in a denied range, or outside every allowed range when any are
configured, reads as toggle "off": the bootstrap payload renders the private
landing page and anonymous creation returns the same 403 "Public sharing
disabled", so the rule's existence is not advertised. Membership is judged
through the request's `env['otto.ip_match']` closure (threaded to the logic
layer as `strategy_result.metadata[:ip_match]` and to the view layer as
`view_vars['ip_match']`), never against the privacy-masked `otto.client_ip`.
A domain with rules fails closed when the request carries no matcher. Owners
and org members are unaffected (the member check runs first), and so is
`POST /api/incoming/secret`, which is gated by `IncomingConfig` readiness
rather than by `HomepageConfig`.

## `POST /api/v3/secret/conceal` (auth=sessionauth)

The strategy layer rejects anonymous before our code runs. Only authenticated
requests reach `validate_domain_permissions`:

| Caller | Custom domain, toggle off | Custom domain, toggle on | Canonical (share_domain=other custom) |
|---|---|---|---|
| Owner / org member | ✓ allowed | ✓ allowed | ✓ allowed |
| Authenticated non-owner | 403 "You do not have permission" | 403 "You do not have permission" | 403 "You do not have permission" |

## `POST /api/v3/guest/secret/conceal` (auth=noauth)

V3 adds `require_guest_route_enabled!(:conceal)` before `super`
(`apps/api/v3/logic/secrets.rb:54-57`). This raises `Onetime::GuestRoutesDisabled`
(403) **only when** `anonymous_user? && auth_method == 'noauth'`
(per `guest_context?` at `lib/onetime/logic/guest_route_gating.rb:81-83`).
Authenticated callers passing through this route bypass the guest gate.

| Caller | Site `guest_routes.conceal` | Custom domain, toggle off | Custom domain, toggle on | Canonical (share_domain=other) |
|---|---|---|---|---|
| Anonymous | disabled | 403 GuestRoutesDisabled (before us) | 403 GuestRoutesDisabled | 403 GuestRoutesDisabled |
| Anonymous | enabled | 403 "Public sharing disabled" | ✓ allowed (public intake) | 403 "You do not have permission" |
| Authenticated owner | n/a (gate skipped) | ✓ allowed | ✓ allowed | ✓ allowed |
| Authenticated non-owner | n/a (gate skipped) | 403 "You do not have permission" | 403 "You do not have permission" | 403 "You do not have permission" |

## Implementation References

- `apps/api/v2/logic/secrets/base_secret_action.rb` — `validate_domain_permissions`
- `apps/api/v3/logic/secrets.rb` — guest route gating via `require_guest_route_enabled!`
- `lib/onetime/logic/guest_route_gating.rb` — `guest_context?` predicate

## Test Coverage

Each row in these tables maps to a parameterized test case. See
`try/unit/logic/secrets/base_secret_action_try.rb` for the test matrix.
