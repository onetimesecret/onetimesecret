# docs/specs/domain-resolution/domain-resolution.md

## created: 2026-08-13

# Domain Resolution

## Problem space

The application serves two types of domains:

1. **Operator domains** — the main application domain and its recognized subdomains.
   These use the operator’s global settings for sign-in and sign-up.

2. **Customer custom domains** — domains owned by tenants/customers.
   These are intentionally more restrictive: sign-in and sign-up are off unless the tenant explicitly enables them.

Before applying those rules, `DomainStrategy` classifies the request host as:

- `:canonical` — main operator domain
- `:subdomain` — recognized operator subdomain
- `:custom` — known customer domain
- `:invalid` — unknown or invalid domain

### The ambiguity

`:invalid` currently means two different things:

- The hostname genuinely is not recognized or is malformed.
- The hostname is a real customer domain, but the custom-domain datastore lookup temporarily failed.

The code cannot distinguish those cases after classification.

### Why it matters

Many consumers use a check equivalent to:

> “Is this exactly a custom domain?”

If the answer is no, they take the operator-domain behavior.

That is harmless for presentation details such as logos or favicons. It is unsafe for sign-in and sign-up:

- A custom domain with no per-domain configuration defaults to **off**.
- An operator domain follows the global setting, which may be **on**.

So a transient Redis/datastore failure can cause a customer domain to be classified as `:invalid`, then treated like the operator site. If global signup is on, the customer’s domain can temporarily allow signup even though that customer never enabled it. Sign-in has the same inverted-default risk.

This is an availability failure turning into an access-policy widening.

## Constraints on a fix

A fix should preserve two distinct behaviors:

- A genuinely unknown/malformed host should retain its current generic, non-tenant presentation.
- A host that might be a customer domain must not gain operator authentication defaults merely because the app could not confirm its identity.

It must also respect an important classifier property:

- A datastore failure cannot create a `:canonical` or `:subdomain` result.
- It can turn a custom domain—and currently a subdomain—into `:invalid`.

Therefore only a **positive** `:canonical` or `:subdomain` classification is sufficient evidence to apply operator defaults. “Anything other than `:custom`” is not sufficient evidence.

## Potential solutions

### 1. Resolver-side fail-closed behavior

Pass the request’s domain classification into the sign-in and sign-up resolvers.

The resolver would apply the operator/global default only when the classification is positively known to be operator-owned:

```text
canonical or subdomain → use global/operator default
custom, invalid, missing → use tenant-safe default
```

For sign-in/sign-up, the tenant-safe default is disabled unless the tenant’s own configuration explicitly enables it.

**Benefits**

- Fixes the actual security issue.
- Keeps generic/unknown-host rendering behavior unchanged.
- Centralizes this security rule at the policy-resolution layer.
- Matches the existing `SigninConfig.operator_host?` approach used for unreadable-policy failures.

**Trade-off**

- During an outage, a recognized operator subdomain can be treated more strictly than normal because it may become `:invalid`. That is a fail-closed availability cost, not an access widening.

### 2. Preserve failure provenance in the classifier

Instead of collapsing all failures into `:invalid`, return a more specific classification, such as:

```text
:invalid_host
:custom_lookup_unavailable
```

Consumers could then explicitly handle the latter as a tenant-safe failure.

**Benefits**

- Accurately represents what happened.
- Could help logging, metrics, response status choices, and future policies.

**Trade-offs**

- Requires updating every consumer of domain classification.
- Easy to miss a consumer and recreate inconsistent behavior.
- Broader change than the issue requires.

This may be useful later, but it is not necessary to close the security gap.

### 3. Change `custom_domain_request?` so anything non-operator is tenant-like

One tempting fix is to redefine “custom domain request” as:

```text
not canonical and not subdomain
```

That would cause `:invalid` hosts to receive tenant behavior.

**Why this is wrong**

It also treats genuinely malformed and unknown hostnames as tenant domains. That can incorrectly apply tenant branding, tenant routing, or other tenant-specific behavior where no tenant exists. It fixes one policy decision by breaking the intended meaning of unrelated presentation and routing decisions.

The issue explicitly rules this approach out.

### 4. Fail all `:invalid` requests with a 503 — possible but too broad

The application could reject every request classified as `:invalid`.

**Benefits**

- Prevents accidental fallback to operator policy.

**Trade-offs**

- Changes normal behavior for unknown/malformed hosts.
- Makes a generic bad-host condition look like a service outage.
- Affects cosmetic and public routes unnecessarily.
- Does not distinguish a hostile/invalid host from a temporary infrastructure problem.

This is generally too blunt unless the application wants a separate host-validation policy.

### 5. Retry the custom-domain lookup — supplementary only

The classifier could retry transient datastore reads before returning `:invalid`.

**Benefits**

- Might reduce the frequency of misclassification.

**Why it is insufficient**

- A retry can still fail.
- It adds latency during degraded infrastructure.
- It does not establish the safe behavior when the retry also fails.

Retries can complement, but cannot replace, a fail-closed policy decision.

---

## Assessment

The problem statement and core security analysis are correct.

This is a fail-open authorization-policy bug:

```text
custom domain
→ datastore lookup fails
→ :invalid
→ “not custom”
→ operator/global default
→ authentication may become enabled
```

A classification failure must not widen authentication access.

## Recommended solution

Resolver-side fail-closed behavior is the best targeted fix. Operator defaults should require positive evidence:

```ruby
SigninConfig.operator_host?(domain_strategy)
```

Only `:canonical` and `:subdomain` should inherit operator defaults. `:custom`, `:invalid`, and `nil` should use tenant-safe semantics.

The other proposed solutions are correctly rejected or deferred:

- Changing `custom_domain_request?` would contaminate branding and routing semantics.
- Returning 503 for every `:invalid` host changes unrelated unknown-host behavior.
- Retrying does not define safe terminal behavior.
- Preserving failure provenance is useful observability work, but broader than necessary.

## Implementation refinements

### 1. Update every authentication decision surface

The runtime controller is not the only relevant consumer.

Current operator-fallback behavior exists in:

- `apps/web/core/controllers/base.rb`
  - `signin_enabled?`
  - `signup_enabled?`
- `apps/web/core/views/serializers/config_serializer.rb`
  - `resolve_signin`

If only the controller changes, the `/signin` page can advertise availability while the POST route rejects it. The existing comments explicitly require display/runtime parity.

Signup presentation paths should also be checked, although `DomainSerializer` already uses the custom-domain-specific resolver.

### 2. Avoid silently changing context-free resolver semantics

The current generic methods have established operator-style behavior:

```ruby
resolve_signin_enabled(global, nil) # global
resolve_signup_enabled(global, nil) # global
```

They are also used internally by the custom-domain resolvers and by non-request contexts. Making an omitted `domain_strategy` implicitly mean tenant-safe could alter administrative/API calculations unexpectedly.

Prefer either:

```ruby
resolve_signin_enabled(global, config, domain_strategy:)
resolve_signup_enabled(global, config, domain_strategy:)
```

with a required keyword for request-aware calls, or add explicitly named request resolvers:

```ruby
resolve_signin_enabled_for_request(...)
resolve_signup_enabled_for_request(...)
```

The request-aware resolver can delegate to the existing operator/custom resolvers:

```ruby
if SigninConfig.operator_host?(domain_strategy)
  resolve_signin_enabled(global, config)
else
  resolve_signin_enabled_for_custom_domain(global, config)
end
```

This keeps existing context-free semantics explicit and minimizes accidental regressions.

### 3. Preserve the sign-in SSO distinction

`resolve_signin_enabled_for_custom_domain` has two intentional modes:

- Runtime password/email POST gate: no `domain_id`, strictly disabled without enabled `SigninConfig`.
- Display gate: receives `domain_id`, allowing the independently configured tenant-SSO carve-out.

The classification-aware change must preserve that distinction. It should not accidentally hide valid tenant SSO or allow SSO configuration to enable password/email POST handling.

### 4. Treat unreadable tenant configuration as unavailable

“Disabled unless explicitly enabled” means the application must successfully read the tenant policy. If the follow-up `SigninConfig` or `SignupConfig` lookup also fails, the application cannot establish explicit enablement and must remain closed.

The sign-in path already has `SigninPolicyUnavailable` handling. Verify signup has equivalent failure handling; classification-aware resolution alone does not protect against a later policy read raising.

## Required test matrix

For global authentication enabled and no tenant configuration:

| Classification | Expected |
| -------------- | -------: |
| `:canonical`   |  enabled |
| `:subdomain`   |  enabled |
| `:custom`      | disabled |
| `:invalid`     | disabled |
| `nil`          | disabled |

Also test:

- Global disabled remains disabled for every classification.
- Enabled tenant config can only narrow the global capability.
- `:invalid` with successfully resolved, explicitly enabled tenant config follows the intended policy.
- Unreadable tenant policy fails closed.
- Runtime and serialized/display results agree.
- Sign-in SSO-only display behavior remains available while password/email POST remains disabled.
- String classifications, if accepted through `operator_host?`, behave consistently with symbols.

## Conclusion

Solution 1 is the correct immediate remediation, with one qualification: implement it as a request-aware policy resolver and propagate it to both runtime and display consumers. Do not redefine domain identity predicates. Preserve failure provenance later for diagnostics and metrics, but it is not required to close this access-policy widening.

## Long-term mitigation

The durable solution is **typed classification with explicit trust and failure provenance**, combined with **centralized policy resolution**.

Solution 1 should remain the security boundary. Solution 2 should eventually improve the information supplied to that boundary.

### 1. Replace ambiguous symbols with a structured result

`DomainStrategy` should return an object rather than a bare symbol:

```ruby
DomainResolution.new(
  classification: :custom,
  trust: :confirmed,
  host: normalized_host,
  tenant_id: domain_id,
)
```

Failure example:

```ruby
DomainResolution.new(
  classification: :unknown,
  trust: :indeterminate,
  reason: :custom_lookup_unavailable,
  host: normalized_host,
)
```

Useful states include:

- Confirmed operator host
- Confirmed customer host, ideally including `tenant_id`
- Confirmed unknown or malformed host
- Indeterminate because tenant lookup was unavailable

The critical distinction is not merely `:invalid_host` versus `:custom_lookup_unavailable`. It is:

```text
confirmed operator
confirmed tenant
confirmed non-tenant
indeterminate
```

### 2. Make authentication policy consume positive authority

Centralize request policy resolution:

```ruby
AuthenticationPolicy.for(domain_resolution)
```

Its invariant should be:

```text
Operator defaults require a confirmed operator classification.
Tenant permissions require confirmed tenant identity and readable tenant policy.
Everything indeterminate fails closed.
```

This avoids negative tests such as:

```ruby
strategy != :custom
```

Individual controllers and serializers should consume the resolved policy rather than interpret domain classifications themselves.

### 3. Separate identity, presentation, and security decisions

A single predicate such as `custom_domain_request?` should not control unrelated concerns.

Use distinct interfaces:

```ruby
resolution.presentation_context
resolution.routing_context
resolution.authentication_authority
```

That permits:

- Unknown hosts to retain generic presentation.
- Indeterminate hosts to avoid tenant branding.
- Authentication to remain closed whenever operator ownership is not positively established.

Generic presentation does not imply operator authorization.

### 4. Resolve tenant identity once

When custom-domain lookup succeeds, include the tenant/domain identifier in the resolution object. Downstream code should not independently repeat:

```ruby
CustomDomain.load_by_display_domain(host)
```

Repeated reads create inconsistent snapshots:

1. Middleware lookup succeeds.
2. A later lookup fails or returns different data.
3. Routing, branding, and authentication disagree.

One request should carry one authoritative domain-resolution result. Tenant policy reads can then use its confirmed `tenant_id`.

### 5. Define explicit failure behavior

For an indeterminate domain:

- Authentication-enabling endpoints: reject, preferably with `503`.
- Public/generic rendering: continue where safe.
- Tenant-specific routing or sensitive operations: reject.
- Branding: use generic presentation.
- Logs and metrics: record lookup unavailability separately from invalid input.

This preserves availability for harmless routes without widening access.

### 6. Enforce the invariant structurally

Use exhaustive handling instead of permissive `else` branches:

```ruby
case resolution.authentication_authority
when :operator
  operator_policy
when :tenant
  tenant_policy
when :none, :indeterminate
  disabled_policy
else
  raise "Unhandled authentication authority"
end
```

Adding a new classification should cause tests—or preferably runtime construction validation/static exhaustiveness—to fail until its security behavior is chosen explicitly.

Ban direct classification interpretation outside the domain-resolution/policy layer.

### Migration path

1. **Immediately:** implement classification-aware, fail-closed request resolvers.
2. Introduce `DomainResolution` while retaining compatibility accessors for existing consumers.
3. Carry confirmed `tenant_id` in the resolution.
4. Move authentication decisions into one request-level policy object.
5. Migrate consumers by concern: authentication first, then routing and presentation.
6. Remove direct symbol comparisons after all consumers migrate.
7. Add metrics for malformed, unknown, and lookup-unavailable outcomes.

## Bottom line

The long-term design is not classifier provenance alone. It is:

> **Structured domain resolution, positive authority checks, one resolution per request, and centralized fail-closed security policy.**

That makes an ambiguous or newly introduced classification unable to inherit operator permissions accidentally.
