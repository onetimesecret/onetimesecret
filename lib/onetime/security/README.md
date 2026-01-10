# lib/onetime/security/README.md
---

# Onetime::Security

Layer-agnostic security logic for the Onetime Secret application.

## Scope

This namespace contains security-related code that is **not coupled to a specific architectural layer**. For example, code here has no Rack dependency and can be called from request handlers, background jobs, tests, or CLI tooling.


### Guidelines

Prefer more specific namespaces when appropriate:

- Authentication logic → `Auth::*`
- Encryption primitives → `Crypto::*`
- General utilities → `Utils::*`

This namespace is for security concerns that don't fit cleanly elsewhere.


### Relationship to Middleware::Security

`Middleware::Security` configures Rack middleware (CSRF protection, XSS headers, etc.) and belongs in the `Middleware::*` namespace alongside other Rack components. This namespace is for security logic that operates independently of the HTTP request lifecycle.

**Heuristic:** If removing the Rack gem would break the code, it belongs in `Middleware::*`. If not, it's a candidate for `Security::*`.
