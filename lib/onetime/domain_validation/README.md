# Domain Validation Module

Custom domain SSL and DNS validation strategies.

## Strategies

| Strategy | SSL Certs | DNS Widget | Use Case |
|----------|-----------|------------|----------|
| `approximated` | Managed | Yes | Approximated.app service |
| `caddy_on_demand` | Auto | No | Caddy on-demand TLS |
| `passthrough` | External | No | Manual/external certs |

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
- `caddy_on_demand_strategy.rb` - Caddy delegation

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
strategy.validate_ownership(custom_domain)  # DNS TXT validation
strategy.request_certificate(custom_domain) # SSL provisioning
strategy.check_status(custom_domain)        # Current status

# Management (Approximated only)
strategy.delete_vhost(custom_domain)        # Remove from provider
strategy.get_dns_widget_token               # Token for DNS widget

# Capability checks
strategy.supports_dns_widget?     # => true for approximated
strategy.manages_certificates?    # => true for approximated
```
