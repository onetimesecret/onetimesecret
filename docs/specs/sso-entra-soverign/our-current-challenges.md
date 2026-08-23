# docs/specs/sso-entra-soverign/our-current-challenges.md
---

## Background

Supporting Entra national/sovereign clouds is a common SSO concern, especially for products used by government or regulated customers. The underlying problem is normal: Microsoft has multiple trusted identity-cloud authorities, and a tenant’s cloud determines its authorization, token, discovery, and issuer endpoints.

The added tension here comes from implementation choices, not from SSO itself:

- **`entra_id` treats Microsoft’s commercial host as an invariant.** It has a static authority rather than a selected, validated cloud authority. That makes commercial Entra simple, but prevents national-cloud use.
- **The redirect target, token issuer validation, discovery test, and CSP origin are configured in different places.** All must agree on the same authority. Currently some are commercial-hardcoded while CSP can be overridden separately, so CSP can be made permissive without making sign-in work.
- **CSP is inferred from the issuer in the generic OIDC path.** Usually that is sufficient, but it is not universally correct: an IdP may publish an `authorization_endpoint` on a different origin.
- **There are two configuration surfaces:** platform/environment configuration and per-domain records. They need equivalent authority behavior, but are implemented through different paths and can drift.

None of this is unusually hard, but it needs a clear source of truth. A robust design is:

1. For built-in Entra support, store a fixed `cloud`/`authority` enum mapped to known Microsoft hosts.
2. Use that mapping consistently for authorization, token exchange, issuer validation, discovery, connection tests, and CSP.
3. For generic OIDC, use the discovery document—especially `authorization_endpoint`—as the authority for redirect/CSP decisions, with careful caching and validation.
4. Keep manual CSP overrides only as an explicit escape hatch for unavailable or nonstandard metadata.

So the current limitation is not inherent to SSO or sovereign Entra. It is the consequence of optimizing the built-in provider around the commercial-cloud default while the rest of the system supports more dynamic OIDC configuration.


## To support sovereign Entra properly

Small, contained change — one field, three call sites, one host map:

1. Add a cloud (or authority) field to SsoConfig, enum commercial|us_gov|china mapped to fixed hosts. Validate against the map, never free-form, so it can't become an open redirect surface.
2. build_entra_id_options: pass base_url: when non-commercial. The gem supports it (entra_id.rb:56 for authorize/token URLs, :177 for iss verification), and omitting the key preserves today's commercial default.
3. test_connection.rb: build the discovery URL from the same map instead of the hardcoded commercial one.
4. AuthConfig: make entra's origin authority-aware — extend tenant_origin_source / ISSUER_DERIVED_PROVIDER_TYPES so entra_id derives from the mapped authority rather than the static registry definition. The registry header on this branch already flags this as the constraint that has to move.

Then drop the "tenant Entra is commercial-cloud only" carve-out from .env.reference, per-domain-sso.md, per-install-sso.md, and the registry header, and add the cloud selector to the domain SSO form.

Separately and worth more than the above: derive the CSP origin from the discovery document's authorization_endpoint (cached) instead of the issuer. That kills the whole split-endpoint class — v1 issuers, B2C, non-Microsoft IdPs — rather than just the Entra sovereign case, and would let SSO_FORM_ACTION_ORIGINS retire from tenant reasoning entirely.
