# Domain Validation Module

Custom domain SSL and DNS validation strategies.

## Strategies

| Strategy | Ownership check | SSL Certs | DNS Widget | Use Case |
|----------|-----------------|-----------|------------|----------|
| `approximated` | TXT record, via the Approximated API with our own lookup as fallback | Managed | Yes | Approximated.app service |
| `caddy_on_demand` | TXT record, via our own lookup | Auto | No | Caddy on-demand TLS |
| `passthrough` | None | External | No | Manual/external certs |

## Ownership check

`validate_ownership` has three outcomes (see `base_strategy.rb`):

| `validated` | Meaning | Effect on the stored `verified` flag |
|-------------|---------|--------------------------------------|
| `true` | Exactly one TXT value at the domain's validation record, equal to the challenge | Set to true |
| `false` | The resolver stated the record is missing (NXDOMAIN, or NOERROR without TXT data) or the values are not exactly one match | Set to false, unless a Colonel override holds it |
| `nil` (+ `indeterminate: true`) | No answer: SERVFAIL, REFUSED, timeout, network error | Left unchanged, for at most 7 days (see below) |

`TxtVerifier` implements this with `TxtResolver`, a small resolver that reads the DNS response code. `Resolv::DNS#getresources` cannot be used for it: it returns `[]` for NXDOMAIN, SERVFAIL and a timeout alike.

Under `caddy_on_demand` the TXT check is the ownership proof. Caddy completing an ACME challenge shows that the name resolves to this deployment; it does not show which account, if any, controls the domain. The internal ACME endpoint (`apps/internal/acme`) only authorises a certificate for a domain that is `ready?`, which requires `verified`.

Under `approximated` the API's answer is used when it has one. When its own DNS lookup failed (`actual_values: false`), `TxtVerifier` decides instead, with the same three outcomes.

### Confirmation window

An indeterminate check may not hold `verified` indefinitely. `VerifyDomain::ConfirmationWindow` (`lib/onetime/operations/verify_domain/confirmation_window.rb`) keeps two timestamps on `CustomDomain`:

- `verified_confirmed_at`: the last passing check.
- `verified_unconfirmed_since`: the first indeterminate check of a verified domain since then. Any definitive answer clears it.

When a check is indeterminate and `verified_unconfirmed_since` is more than 7 days old (`ConfirmationWindow::MAX_AGE`), `verified` is withdrawn. The result reports `dns_outcome: confirmation_expired`, bulk results count it in `confirmation_expired_count`, and VerifyDomain logs a warning.

The window runs from the first indeterminate check, not from the last passing one. A deployment that does not run `DomainRefreshJob` may check a domain once in months, and one resolver failure on that check must not demote it. A demotion always takes two indeterminate checks at least 7 days apart with no passing check between them.

- A domain with no clock, which is every domain at upgrade, starts one on its first indeterminate check and is not demoted by that check.
- A Colonel override exempts the domain, as it does for a definitive failure.
- Unverified domains are not affected.
- A demoted domain becomes verified again on its next passing check.

## Bulk pacing

`bulk_rate_limit` is the pause, in seconds, a bulk run takes between domains. `approximated` declares 0.5 for its API rate cap; the other strategies declare none. `VerifyDomain` uses it for bulk runs unless the caller passes `rate_limit:` (the `jobs.domain_refresh.rate_limit` setting, or `bin/ots domains verify --all --rate-limit N`), which overrides the strategy, including with 0.

## Status check

`check_status` reports two things, each with the same three outcomes (`true`, `false`, `nil` = could not tell). `nil` never changes stored state.

| | Stored in | `approximated` | `caddy_on_demand` | `passthrough` |
|---|---|---|---|---|
| `is_resolving` | `CustomDomain#resolving` | Approximated's claim (`nil` while its status is `UNKNOWN`) | Our own A/AAAA lookup | Always `true` |
| `has_ssl` | inside the `vhost` blob (`:data`) | Approximated's claim | Our own TLS handshake | Always `true` (nothing stored) |

Caddy has no per-domain status API, so `caddy_on_demand` uses `TlsProbe`:

1. `AddressResolver` looks up A and AAAA and reads the response code. An address means `is_resolving: true`; NXDOMAIN or an empty NOERROR from both families means `false` (and `has_ssl: false`); SERVFAIL, REFUSED or a timeout means `nil` for both.
2. The addresses go through the shared egress guard (`Onetime::Http::Guard.validate_addresses!`). The hostname is customer-controlled, so if any address is loopback, private, link-local or otherwise reserved, nothing is dialled: `is_resolving: true`, `has_ssl: nil`.
3. The probe connects to a vetted IP on port 443 (never re-resolving the name), sends the hostname as SNI, completes a handshake with chain and hostname verification, and closes. No application data is sent. A verified handshake is `has_ssl: true`. A TLS error, an untrusted or mismatched certificate, or a refused or dropped connection is `false`. A timeout or an unroutable address is `nil`.

`resolving` only means the name has an address record. It does not wait for a certificate, because the ACME ask endpoint requires `resolving` before Caddy may obtain one. It also does not check that the address is this deployment's; the certificate check is what shows that.

How the result is stored (`VerifyDomain#persist_changes`):

- `is_resolving` `true`/`false` is written to `resolving`; `nil` is skipped.
- `has_ssl` exists only inside the `vhost` blob, so the strategy returns `:data` only when `has_ssl` is known. The blob uses the keys the domain pages already read (`status`, `status_message`, `has_ssl`, `is_resolving`, `dns_pointed_at`, `ssl_active_from`, `ssl_active_until`, `last_monitored_unix`) plus `source: tls_probe`. `status` is `ACTIVE_SSL`, `PENDING_SSL` (resolves, no valid certificate yet) or `DNS_INCORRECT` (does not resolve).
- When the probe could not tell anything, the strategy returns neither `:data` nor `:mode`. Nothing stored changes and `vhost_fetch_failed_at` is set, which the UI shows as a failed check.
- A `vhost` blob written under `approximated` is never replaced by the probe. After a strategy cutover it is the only record of the remote vhost; see the cleanup chore below. Once that blob is cleared the probe's blob takes its place.

Time budget per domain: address lookup 3s, connect plus handshake 5s, each spent only on a timeout. `DomainRefreshJob` runs the TXT check and this probe for every domain on its page; the job's header comment works out the per-page ceiling.

A certificate from a private CA (for example Caddy's `tls internal`) fails verification against the system trust store and is reported as `has_ssl: false`.

## Configuration

Configure in `config.yaml`:

```yaml
features:
  domains:
    validation_strategy: approximated  # or passthrough, caddy_on_demand
    approximated:
      api_key: xxx
      proxy_ip: 1.2.3.4
      proxy_host: proxy.example.com
      proxy_name: Production Proxy
      vhost_target: target.example.com
```

## Moving off `approximated`

Changing `validation_strategy` away from `approximated` does not delete anything on Approximated. Each domain provisioned before the change keeps its vhost there (billable, and able to serve the hostname for as long as DNS points at the cluster) and keeps the old `vhost` JSON on its `CustomDomain` record. The `remove_orphaned_approximated_vhosts` housekeeping chore cleans both up.

Keep `approximated.api_key` and `proxy_ip` / `proxy_host` configured after the cutover. The chore needs the key to delete and the proxy address to tell which domains still point at the cluster. The chore reads `proxy_ip` as one or more entries separated by commas or spaces, each a single address or a CIDR range such as `203.0.113.0/24`. The same value is shown to customers as the A record target in the domain setup screens, so only widen it once no domain is still being set up against Approximated.

```bash
# Dry run (default): lists deletion candidates, makes no Approximated API call
bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts

# Delete
APPROXIMATED_VHOST_CLEANUP=apply bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts
```

A vhost is deleted only when the domain resolves, from this host, to addresses outside the Approximated cluster, and Approximated itself reports the vhost as not resolving and not receiving traffic. A domain that still points at the cluster, has no DNS answer, or is served through another proxy (`ACTIVE_SSL_PROXIED`) is skipped and picked up again on the next run. The nightly HousekeepingJob runs the chore as a dry run unless the variable is set in its environment. `verified`, `resolving` and the TXT fields are never changed.

Under `caddy_on_demand` a domain's SSL status on the domain pages keeps showing the old Approximated data until the chore has cleared its `vhost` JSON; the status probe fills the field from then on (see Status check). `resolving` is updated by the probe regardless. The chore ignores `vhost` JSON the probe wrote (`source: tls_probe`).

Re-run until the dry run reports no candidates. Domains that are skipped every time (no DNS answer, proxied, renamed, or a stored `vhost` value that is not valid JSON, which is logged as a warning) need a manual decision in the Approximated dashboard.

## Files

- `features.rb` - Config accessor (strategy, API keys, proxy settings)
- `strategy.rb` - Factory for creating strategy instances
- `base_strategy.rb` - Interface definition
- `approximated_strategy.rb` - Approximated.app implementation
- `approximated_client.rb` - HTTP client for Approximated API
- `passthrough_strategy.rb` - No-op for external cert management
- `caddy_on_demand_strategy.rb` - TXT ownership check and probe-based status; certificates delegated to Caddy
- `txt_verifier.rb` - TXT ownership check with three outcomes (shared by the strategies above)
- `txt_resolver.rb` - TXT lookup that reports the DNS response code
- `address_resolver.rb` - A/AAAA lookup that reports the DNS response code
- `dns_stub_resolver.rb` - Transport and time budget shared by the two resolvers
- `tls_probe.rb` - Resolution and certificate check for `caddy_on_demand` status, behind the egress guard

## DNS Widget Integration

The Approximated strategy supports a DNS widget that auto-detects DNS providers and provides step-by-step instructions or automated updates.

**Backend**: `strategy.get_dns_widget_token` returns a token for the widget.

**Frontend**: Widget assets are self-hosted in `src/assets/approximated/`:
- `dnswidget.v1.js`
- `dnswidget.v1.css`

The widget renders only when `validation_strategy === 'approximated'` (see `DomainVerify.vue`).

## Usage

```ruby
strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)

# Core operations
strategy.validate_ownership(custom_domain)  # DNS TXT validation (approximated, caddy_on_demand)
strategy.request_certificate(custom_domain) # SSL provisioning
strategy.check_status(custom_domain)        # Current status

# Management (Approximated only)
strategy.delete_vhost(custom_domain)        # Remove from provider
strategy.get_dns_widget_token               # Token for DNS widget

# Capability checks
strategy.supports_dns_widget?     # => true for approximated
strategy.manages_certificates?    # => true for approximated
```
