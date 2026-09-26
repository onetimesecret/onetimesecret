> **Status (2026-09-25):** The SAML motivation below is resolved. #4450 replaced the global `SameSite=None; Secure` prerequisite with a staged POST → 303 → GET callback transport that recovers the ordinary `SameSite=Lax` cookie (`Strict` unsupported, `None` still works); see [docs/authentication/saml-callback-transport.md](../../authentication/saml-callback-transport.md). Apple still requires `None`. The per-session SameSite design below is unimplemented and kept as written.

The likely implementation scope, constraints, and test coverage needed for per-session SameSite.

The code confirms that `rack-session` can choose `SameSite` dynamically at cookie commit time, but the timing and concurrency details matter. I’m now checking GitHub directly and verifying the exact middleware/API points before recommending an approach.

GitHub has no standalone issue matching this feature. Issue `#4450` contains the SAML work and current global-cookie prerequisite; I’m checking its discussion and the earlier SameSite issue to determine whether this enhancement is already tracked implicitly.

## Conclusion

This is feasible with the current `rack-session` version and does not require replacing the session system.

The practical implementation is:

1. Keep `site.session.same_site: lax` as the default.
2. Mark a session as temporarily requiring a cross-site POST callback when starting Apple or SAML authentication.
3. Supply `rack-session` with a callable `same_site` policy:
   - return `:none` while that marker is active;
   - otherwise return the configured default, normally `:lax`.
4. Clear the marker after the callback succeeds or fails.

This would limit `SameSite=None` to the session and time window that require it. A separate SSO correlation cookie would provide stronger isolation but would require substantially more work.

## Current behavior

Session policy is installation-wide:

- Default: `SameSite=Lax` in `lib/onetime/boot.rb:87-91`.
- Middleware passes a fixed value to `Onetime::Session` in `lib/onetime/application/middleware_stack.rb:665-674`.
- SAML currently requires the operator to globally configure `SameSite=None; Secure`:
  - validation: `lib/onetime/sso_provider/saml.rb:413-421`
  - boot warning: `apps/web/auth/config/features/omniauth.rb:670-684`
  - tenant configuration rejection: `apps/api/domains/logic/sso_config/saml_fields.rb:109-121`

Apple documents the same requirement but does not enforce it at configuration time.

SAML and Apple need `None` because their identity providers return through cross-site POST callbacks. Ordinary OIDC, Entra, Google, GitHub, and Stripe redirects can remain `Lax`.

## Framework support

The current `rack-session` 2.1.2 implementation supports a callable `same_site` option. It evaluates that callable when committing the response cookie:

```ruby
same_site: ->(request, response) { ... }
```

A middleware that only changes `env['rack.session.options'][:same_site]` would **not** work. `rack-session` removes `same_site` from the normal per-request options during initialization and stores it separately.

The policy must emit `SameSite=None` on the **initiation response**, before redirecting the browser to the IdP. Changing the policy only on the callback is too late because the browser has already decided whether to include the cookie.

## Recommended design

### 1. Add provider capability metadata

Mark providers whose callback is a cross-site POST, rather than hard-coding provider names throughout the middleware:

```ruby
cross_site_post_callback: true
```

Set it for:

- Apple
- SAML

Leave it false or absent for OIDC, Entra, Google, and GitHub.

The existing provider definitions in `lib/onetime/sso_provider/apple.rb` and `lib/onetime/sso_provider/saml.rb` are the appropriate source of this capability. This also respects `APPLE_ROUTE_NAME` and `SAML_ROUTE_NAME` overrides.

### 2. Set a bounded session marker during request phase

During the validated OmniAuth initiation request, set something equivalent to:

```ruby
session['cross_site_auth'] = {
  'provider' => strategy.name,
  'expires_at' => Time.now.to_i + 300
}
```

The relevant initiation hook is `omniauth_request_validation_phase` in `apps/web/auth/config/hooks/omniauth.rb:574-650`.

The marker should include:

- provider route name;
- expiration time;
- optionally a flow identifier if simultaneous flows need support.

A five-minute lifetime would align with the existing short-lived SSO Connect intent described in that hook, but the exact value should be selected explicitly.

### 3. Use a `SameSite` policy callable

Replace the fixed value at `lib/onetime/application/middleware_stack.rb:673` with a callable that:

- reads the configured default;
- inspects the loaded Rack session;
- returns `:none` while a non-expired cross-site-auth marker exists;
- returns the configured default otherwise.

This can be a small dedicated policy object rather than an inline lambda so its behavior can be unit-tested.

### 4. Clear the marker through all callback outcomes

Clear it after:

- successful Apple or SAML callback;
- provider-declared authentication failure;
- malformed callback;
- state/nonce failure;
- SAML validation failure;
- cancellation where the IdP returns to the callback.

An abandoned flow cannot actively clear its marker, so expiry is required.

The marker should remain present until callback processing has obtained the session. Clearing it before the callback request is impossible because the callback is precisely the request that needs the `None` cookie.

### 5. Retain the `Secure` prerequisite

Browsers reject `SameSite=None` cookies without `Secure`.

The current SAML compatibility check should therefore change from:

> require global `same_site: none` and `secure: true`

to:

> require `secure: true`; the application selects `SameSite=None` for the SAML flow

For normal HTTPS deployments, `secure` is already the expected setting. Plain-HTTP deployments cannot support Apple or SAML cross-site POST callbacks reliably.

### 6. Remove obsolete global-policy enforcement

After dynamic behavior is tested:

- revise or remove `Saml.session_cookie_problem` in `lib/onetime/sso_provider/saml.rb`;
- retain a secure-cookie compatibility check;
- update the boot warning in `apps/web/auth/config/features/omniauth.rb`;
- stop rejecting tenant SAML configuration merely because the global default is `lax`;
- update `test_connection` and the SAML documentation;
- remove instructions telling operators to set all sessions to `SameSite=None`.

## Concurrency considerations

A simple path-based callable—`None` only on `/auth/sso/apple` and `/auth/sso/saml`—is insufficient.

It emits `None` on initiation, but any concurrent request from another browser tab could subsequently emit the same cookie as `Lax` while the user is at the IdP. The browser would then withhold it from the callback.

A session marker avoids that problem by keeping every cookie refresh for that session at `None` until the flow finishes or expires.

There are still edge cases:

- Multiple browser tabs share one session and therefore share the temporary policy.
- Starting two flows requires either:
  - explicit “latest flow wins” semantics, consistent with current session-bound SAML behavior; or
  - multiple markers keyed by flow/provider.
- An abandoned flow leaves the cookie at `None` until the marker expires.
- Concurrent responses around callback completion can briefly reissue `None`; the next committed response should restore `Lax`.

These are manageable and should be documented in the policy tests.

## Stronger alternative: separate correlation session

A separate short-lived cookie could use:

- `SameSite=None`
- `Secure`
- `HttpOnly`
- a narrow callback path where practical
- only OAuth state/nonce, SAML request ID, tenant context, and connect intent

The primary `onetime.session` cookie would remain `Lax` throughout.

This has the best security boundary, but it is a larger redesign because Rodauth/OmniAuth and the custom SAML strategy currently expect correlation data in the main Rack session. Tenant context and Connect intent also depend on existing session state. It would require adapting or wrapping strategy storage, callback lookup, expiration, replay protection, and session reconciliation.

I would not make this the first implementation unless strict isolation of the authenticated session is a release requirement.

## Required tests

At minimum:

1. **Policy unit tests**
   - default requests emit `Lax`;
   - Apple and SAML pending sessions emit `None`;
   - expired markers emit `Lax`;
   - clearing a marker restores `Lax`;
   - route overrides work;
   - insecure configuration is rejected.

2. **Wire-level cookie tests**
   - Apple initiation response includes `SameSite=None; Secure`;
   - platform SAML initiation includes it;
   - tenant SAML initiation includes it;
   - OIDC/Entra initiation continues to include `SameSite=Lax`.

3. **Callback lifecycle tests**
   - successful callbacks clear the marker;
   - failed callbacks clear it where a callback is received;
   - SAML still finds its pending AuthnRequest;
   - Apple still finds state and nonce;
   - an expired marker fails safely.

4. **Concurrency tests**
   - an unrelated request while SAML/Apple is pending does not downgrade the cookie to `Lax`;
   - define and test behavior for two simultaneous authentication attempts.

Existing relevant test locations include:

- `spec/unit/onetime/sso_provider/saml_spec.rb`
- `apps/web/auth/spec/integration/full_saml_platform/platform_saml_sso_spec.rb`
- `apps/web/auth/spec/integration/full/tenant_saml_sso_spec.rb`
- `apps/web/auth/spec/integration/full/omniauth_csrf_spec.rb`
- `apps/web/auth/spec/config/features/omniauth_providers_spec.rb`
- `spec/unit/onetime/middleware/http_origin_options_spec.rb`

There is currently no Apple callback integration test; one should be added.

## GitHub issue status

I found **no standalone GitHub issue** requesting per-session or per-provider SameSite handling.

Related issues:

- [#4450 — Add SAML SSO strategy](https://github.com/onetimesecret/onetimesecret/issues/4450)
  Mentions that SAML should use whatever solution Apple established, but does not track dynamic cookie policy. The branch implementation currently resolves this by requiring global `SameSite=None`.

- [#2405 — Session cookie same_site:strict breaks Stripe checkout redirect flow](https://github.com/onetimesecret/onetimesecret/issues/2405)
  Changed the default from `Strict` to `Lax`. It explains why `Lax` should remain the general default but does not cover provider-specific `None`.

- [#2729 — Add integration tests for OmniAuth callback flows](https://github.com/onetimesecret/onetimesecret/issues/2729)
  Related to missing callback coverage, but not the cookie-policy implementation itself.

A new issue is warranted. Suggested title:

> Scope `SameSite=None` session cookies to Apple and SAML authentication flows

No files were changed and no tests were run; this was a static code, dependency, and GitHub issue investigation.

---

> Why are we locked at rack-session 2.1.2?


We are not locked to an outdated `rack-session` release. **2.1.2 is the latest version published on RubyGems.**

The declaration is:

```ruby
gem 'rack-session', '~> 2.1.2'
```

in `Gemfile:113`. That constraint permits versions:

```text
>= 2.1.2 and < 2.2.0
```

`Gemfile.lock:340` resolves it to 2.1.2 because no newer compatible—or newer published—version exists.

The constraint was introduced in commit `32212995b1` (`Ruby gem security updates`) alongside the Rack 3.2 floor. I found no comment or history indicating that 2.1.2 was selected to avoid a known regression or because OTS depends on private behavior specific to that patch release.

So “locked rack-session 2.1.2” meant:

- that is the currently resolved dependency;
- its source establishes what the application can do today;
- specifically, 2.1.2 supports a callable `same_site` policy.

It did **not** mean OTS is being held back from a newer version. `bundle outdated rack-session --strict` reports the bundle as up to date.
