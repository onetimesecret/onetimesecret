## TL;DR

Extraction is feasible and the seam is clean — but only if you invert the dependency. The generic, reusable part is "a tiny Rack app implementing Caddy's on-demand TLS `ask` protocol, with a loopback/allowlist guard, that delegates the actual yes/no to a caller-supplied resolver." Everything OneTimeSecret-specific (CustomDomain, Familia/Redis, `ready?` semantics) stays behind a ~10-line adapter in this repo. Trying to extract the app _as written_ would not work well, because most of its weight is OTS plumbing, not ACME logic.

## What's actually in there

`apps/internal/acme/application.rb` is ~160 lines, of which the portable core is small: the `AskHandler` (parse `domain`, 200/400/403), the `LocalhostOnly` middleware, and the fail-closed `domain_allowed?` wrapper. The rest is coupling:

- `Onetime::Application::Base` (306 lines) which pulls in the universal `MiddlewareStack` (414 lines), Familia's JSON serializer, and OT logging.
- `OT.conf` for `should_skip_loading?` and host/port; `OT.ld/info/le` for logging.
- Otto as the router — for a single `GET /ask` route, plain Rack is enough.
- Registry auto-discovery (`apps/**/application.rb` glob).
- `Onetime::CustomDomain` — the one dependency that genuinely matters, and the one a gem must _not_ contain.

## Gem shape

```ruby
# gem side — depends on rack only
use Rack::Caddy::Ask::LoopbackOnly   # or an explicit allowlist
run Rack::Caddy::Ask.new(
  resolver: ->(domain) { ... true/false ... },  # fail-closed on raise
  logger: my_logger
)

# OTS side — thin adapter
resolver: ->(d) { Onetime::CustomDomain.load_by_display_domain(d)&.ready? || false }
```

The gem owns: param validation, status codes, loopback check, fail-closed exception handling, optional logging hooks. The host app owns: the resolver, config, boot, mounting (standalone rackup or mounted in the main process — both of your current modes keep working).

## Concerns, taken in turn

**Security.** Two-sided:

- _Improves clarity_: the current `LocalhostOnly` silently depends on `IPPrivacyMiddleware` having rewritten `REMOTE_ADDR` first (noted in the code comment). A standalone gem must own its trust boundary explicitly — it should check raw `REMOTE_ADDR` by default and require an explicit opt-in (`trusted_proxies:`) before honoring forwarded headers, otherwise a spoofed `X-Forwarded-For: 127.0.0.1` becomes a cert-issuance bypass in someone else's deployment. Getting this default right is the single most important design decision in the gem.
- _New risk_: the gem sits in the certificate-issuance path. A compromised release = certs for arbitrary domains for every user. That means minimal dependencies (rack only), MFA on rubygems, and treating it as security-sensitive despite its size. As a file in your repo it inherits your repo's supply-chain posture; as a gem it needs its own.
- _Housekeeping either way_: the README and `config.ru` comments still document a `check_verification=false` query parameter that the handler deliberately removed ("removed from the HTTP interface to prevent … bypassing DNS verification"). That doc drift is worth fixing regardless of extraction — someone following the README's Caddyfile example would believe they're skipping verification when they aren't.

**Does the base architecture make it harder than necessary?** Yes, mildly — and that's an argument _for_ extraction, not against. `Onetime::Application::Base` + Otto + registry is overkill for one route; the gem version is plain Rack and simpler than what exists today. The genuine architectural friction is boot, not the app: the standalone `config.ru` runs `Onetime.boot! :app` just to reach Redis. A gem doesn't fix that — the adapter still needs CustomDomain loaded — so the standalone-process mode remains as heavy as it is now. (The alternative, having the resolver hit Redis directly, would duplicate CustomDomain's key/verification logic — don't.)

**Maintenance constraints.** The real cost. A ~150-line gem still needs release ceremony, a CI matrix (Ruby versions × Rack 2/3 — your lowercase headers are already Rack 3-safe), CVE responsibility, and tracking Caddy: `ask` is now sugar for the `http` permission module (`permission http` since Caddy 2.7), and the gem's docs need to track that terminology and any future protocol change. Version skew between the gem and OTS is a new failure mode that doesn't exist today. Given the protocol is tiny and stable, the burden is low but nonzero — the main risk is the gem going stale publicly with your name on it.

**Naming.** Convention: dashes mirror the require path. Suggestions, in order of preference:

1. **`rack-caddy-ask`** → `require 'rack/caddy/ask'` — says exactly what it is (Rack, Caddy, the `ask` endpoint).
2. `rack-on-demand-tls` — more future-proof against Caddy renaming `ask`, less discoverable.
3. Avoid `caddy-*` as the prefix — reads as official. "Caddy" is trademarked (Stack Holdings); nominative use in `rack-caddy-ask` is fine, but the README should note it's unaffiliated, and don't use their logo.

I didn't find an existing Ruby gem for this niche, which supports both the "useful to others" and the blog-post angle.

**Unknown unknowns / gotchas to design for:**

- Caddy caches `ask` decisions briefly and can hammer the endpoint under abuse (on-demand TLS is a known DoS vector) — the gem docs should cover Caddy's `on_demand` rate limiting and recommend the reverse-proxy path block you already document.
- IPv6-mapped loopback (`::ffff:127.0.0.1`) — your `IPAddr#loopback?` handles it; keep a spec for it.
- Unix-socket binding (no `REMOTE_ADDR` at all) — decide whether that means allow or deny.
- Slow resolvers (someone else's SQL/HTTP lookup) blocking TLS handshakes — worth a documented timeout expectation, maybe a resolver timeout option.
- Whether to support the "domain exists but unverified" mode as a resolver concern (it is one — keep it out of the gem's HTTP surface, as you already did in the app).

## Recommendation

Do it, sized honestly: a weekend-scale extraction, with the ongoing cost being stewardship rather than code. Concretely: (1) publish `rack-caddy-ask` with resolver injection, loopback-by-default trust, fail-closed semantics, and a hard "no verification-bypass via query string" stance; (2) shrink `apps/internal/acme` to a subclass/adapter that mounts the gem through your registry so `should_skip_loading?`, config, and both deployment modes keep working unchanged; (3) fix the `check_verification` doc drift as part of it. The blog post writes itself around the two interesting decisions: the forwarded-header trust boundary and fail-closed cert gating.

## Supplemental

The `ask` field is formally deprecated: current Caddy errors out if you set both `ask` and a `permission` module, and the config docs say `ask` "will be removed soon" in favor of the `permission` module system, where the built-in replacement is `tls.permission.http` (Caddyfile: `permission http { endpoint ... }`).

Two nuances before committing to the name, though:

1. **The wire protocol didn't change.** `ask <url>` and `permission http` hit the exact same endpoint contract — GET with `?domain=`, 2xx = allow, anything else = deny. The gem implements the _endpoint_, not the Caddy-side module, so either name is technically accurate. What changed is only Caddy's vocabulary for pointing at it.

2. **"permission" is a genuinely bad standalone word for discoverability** — `rack-caddy-permission` out of context sounds like an authorization middleware for Caddy-proxied apps, not a TLS cert gate. But naming against the deprecated term is worse: in a year, nobody configuring Caddy will type "ask".

So yes, I'd drop `rack-caddy-ask`. My updated ranking:

1. **`rack-caddy-tls-permission`** (→ `Rack::Caddy::TLSPermission`) — matches the module ID `tls.permission.http` almost verbatim, which is what people will grep for, and disambiguates "permission."
2. `rack-caddy-permission` — your suggestion; fine, shorter, slightly ambiguous.
3. `rack-on-demand-tls` — still the most future-proof (survives any further Caddy renaming, and other servers could adopt the same contract), but weakest for search.

If it were mine I'd take option 1, mention "on-demand TLS `ask` endpoint" prominently in the gemspec description and README so both generations of terminology are searchable.

Sources: [caddytls automation.go](https://github.com/caddyserver/caddy/blob/master/modules/caddytls/automation.go), [tls.permission.http in Caddyfile — Caddy Community](https://caddy.community/t/how-to-use-tls-permission-http-in-caddyfile-config-format/24395), [Caddyfile support for permission modules · caddy#6260](https://github.com/caddyserver/caddy/issues/6260)

## Invert the dependency

**`rack-caddy-on-demand`** — that's a good middle ground, arguably the best candidate yet. It names the feature ("on-demand TLS") rather than either generation of config keyword (`ask` / `permission`), so it survives Caddy's vocabulary churn, and keeping "caddy" in the name preserves discoverability. It's also the term Caddy's own docs lead with — the docs page is literally titled "On-Demand TLS." Minor quibble: "on-demand" alone doesn't say _TLS_, but the `caddy` prefix carries enough context. I'd take it over my `rack-caddy-tls-permission` suggestion — it's shorter and reads better. Namespace would be `Rack::Caddy::OnDemand`.

**"Invert the dependency"** refers to which direction the code dependency points between the generic HTTP-endpoint logic and the OneTimeSecret-specific domain check.

Today, inside the app, the generic part depends on the specific part: `AskHandler` calls `Application.domain_allowed?`, which calls `Onetime::CustomDomain.load_by_display_domain(domain)` directly (`apps/internal/acme/application.rb:142`). If you extracted the app verbatim, the gem would have to `require` OneTimeSecret's models — Familia, Redis, your config — which makes it useless to anyone else and circular for you.

The inversion flips that arrow: the gem knows nothing about _how_ a domain is approved, only the protocol (parse `?domain=`, return 200/400/403, guard loopback, fail closed). The host application hands it the decision logic as a callable at construction time:

```ruby
# In the gem — no knowledge of any particular backend
app = Rack::Caddy::OnDemand.new(
  resolver: ->(domain) { ... }   # any callable returning true/false
)

# In OneTimeSecret — the entire integration
resolver: ->(d) { Onetime::CustomDomain.load_by_display_domain(d)&.ready? || false }
```

So instead of "generic endpoint depends on OTS models," it becomes "OTS depends on generic gem and injects its policy." That's the classic Dependency Inversion Principle: both sides depend on a small abstraction (the resolver interface — "callable taking a domain string, returning a boolean") rather than the high-level protocol code depending on a concrete low-level implementation. It's the same pattern Caddy itself uses on its side, incidentally: `OnDemandPermission` is an interface, and `tls.permission.http` is just one pluggable implementation. Your gem would be the mirror image on the Rack side — and another team could plug in a resolver backed by Postgres, an API call, or a static list without the gem changing at all.
