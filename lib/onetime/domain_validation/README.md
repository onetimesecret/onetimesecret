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
| `nil` (+ `indeterminate: true`) | No answer: SERVFAIL, REFUSED, timeout, network error | Left unchanged |

`TxtVerifier` implements this with `TxtResolver`, a small resolver that reads the DNS response code. `Resolv::DNS#getresources` cannot be used for it: it returns `[]` for NXDOMAIN, SERVFAIL and a timeout alike.

Under `caddy_on_demand` the TXT check is the ownership proof. Caddy completing an ACME challenge shows that the name resolves to this deployment; it does not show which account, if any, controls the domain. The internal ACME endpoint (`apps/internal/acme`) only authorises a certificate for a domain that is `ready?`, which requires `verified`.

Under `approximated` the API's answer is used when it has one. When its own DNS lookup failed (`actual_values: false`), `TxtVerifier` decides instead, with the same three outcomes.

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

Keep `approximated.api_key` and `proxy_ip` / `proxy_host` configured after the cutover. The chore needs the key to delete and the proxy address to tell which domains still point at the cluster.

```bash
# Dry run (default): lists deletion candidates, makes no Approximated API call
bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts

# Delete
APPROXIMATED_VHOST_CLEANUP=apply bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts
```

A vhost is deleted only when the domain resolves, from this host, to addresses outside the Approximated cluster, and Approximated itself reports the vhost as not resolving and not receiving traffic. A domain that still points at the cluster, has no DNS answer, or is served through another proxy (`ACTIVE_SSL_PROXIED`) is skipped and picked up again on the next run. The nightly HousekeepingJob runs the chore as a dry run unless the variable is set in its environment. `verified`, `resolving` and the TXT fields are never changed.

Re-run until the dry run reports no candidates. Domains that are skipped every time (no DNS answer, proxied, renamed) need a manual decision in the Approximated dashboard.

## Files

- `features.rb` - Config accessor (strategy, API keys, proxy settings)
- `strategy.rb` - Factory for creating strategy instances
- `base_strategy.rb` - Interface definition
- `approximated_strategy.rb` - Approximated.app implementation
- `approximated_client.rb` - HTTP client for Approximated API
- `passthrough_strategy.rb` - No-op for external cert management
- `caddy_on_demand_strategy.rb` - TXT ownership check; certificates delegated to Caddy
- `txt_verifier.rb` - TXT ownership check with three outcomes (shared by the strategies above)
- `txt_resolver.rb` - TXT lookup that reports the DNS response code

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
