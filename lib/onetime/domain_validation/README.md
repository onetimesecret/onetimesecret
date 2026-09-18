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
