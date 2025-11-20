# IP-Based Access Control

Middleware for signaling access mode based on client IP allowlist matching. **Never blocks requests** - instead sets a downstream header that application code can consume to enforce policy.

## Architecture

### Separation of Concerns

```
┌─────────────────┐
│  Infrastructure │  Sets trigger header with shared secret
│  (Proxy/LB)     │  when access control needed
└────────┬────────┘
         │
         ├─── Request with trigger header
         ↓
┌─────────────────┐
│   Middleware    │  Checks IP against allowlist
│ AccessControl   │  Sets mode header (normal/restricted)
└────────┬────────┘
         │
         ├─── Request with mode header
         ↓
┌─────────────────┐
│   Application   │  Reads mode header
│     Logic       │  Enforces access policy
└─────────────────┘
```

### Design Principles

1. **Signal, don't block**: Middleware sets headers, application enforces
2. **Opt-in activation**: Only evaluates when trigger header + secret match
3. **Fail-safe defaults**: Missing/invalid trigger → passthrough (no restriction)
4. **Timing-attack resistant**: Constant-time secret comparison

## Configuration

### Location

Primary config: `etc/access_control.yaml`

### Required Settings

```yaml
access_control:
  enabled: true

  trigger:
    header: 'X-Access-Control-Trigger'
    secret: '<STRONG_RANDOM_SECRET>'  # openssl rand -base64 32

  allowed_cidrs:
    - '10.0.0.0/8'      # Private network
    - '172.16.0.0/12'   # Private network
    - '192.168.0.0/16'  # Private network

  mode:
    header: 'X-Access-Mode'
    allow: 'normal'      # Set when IP matches allowlist
    deny: 'restricted'   # Set when IP doesn't match
```

### Environment Variables

```bash
# Enable/disable
export ACCESS_CONTROL_ENABLED=true

# Trigger configuration
export ACCESS_CONTROL_TRIGGER_SECRET="$(openssl rand -base64 32)"

# IP allowlist (comma-separated CIDRs, no limit)
# Single CIDR:
export ALLOWED_CIDRS="10.0.0.0/8"

# Multiple CIDRs:
export ALLOWED_CIDRS="10.0.0.0/8,172.16.0.0/12,192.168.1.0/24"

# With IPv6 and specific IPs:
export ALLOWED_CIDRS="10.0.0.0/8,172.16.0.0/12,203.0.113.5/32,fc00::/7"

# Custom mode values (optional)
export ACCESS_MODE_ALLOW="normal"
export ACCESS_MODE_DENY="restricted"
```

## Infrastructure Setup

### Reverse Proxy Configuration

The trigger header **must** be set by trusted infrastructure (reverse proxy, load balancer), not by client requests.

#### Caddy Example

```caddyfile
example.com {
    # Homepage access control
    @homepage path /
    handle @homepage {
        header_up X-Access-Control-Trigger "your-shared-secret-here"
        reverse_proxy localhost:3000
    }

    # All other routes passthrough normally
    reverse_proxy localhost:3000
}
```

#### Nginx Example

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    location / {
        # Set trigger header for homepage
        proxy_set_header X-Access-Control-Trigger "your-shared-secret-here";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://localhost:3000;
    }

    location /api {
        # API routes don't trigger access control (no header)
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://localhost:3000;
    }
}
```

#### HAProxy Example

```haproxy
frontend https_frontend
    bind *:443 ssl crt /path/to/cert.pem

    # Set trigger header for homepage
    acl is_homepage path -i /
    http-request set-header X-Access-Control-Trigger "your-shared-secret-here" if is_homepage

    default_backend app_backend

backend app_backend
    server app1 127.0.0.1:3000
```

## Application Integration

### Middleware Stack Setup

Add to middleware stack **before** `IPPrivacyMiddleware` (needs original IPs):

```ruby
# In apps/base_application.rb or Otto initialization
require 'middleware/access_control'

class BaseApplication < Roda
  use Rack::DetectHost
  use Rack::AccessControl, config[:access_control]  # <-- Add here
  use Otto::Security::Middleware::IPPrivacyMiddleware
  # ... other middleware
end
```

### Reading Mode Header in Application Code

#### Route Handlers

```ruby
class WebCore::Controllers::HomeController
  def index(req, res)
    access_mode = req.env['HTTP_X_ACCESS_MODE']

    if access_mode == 'restricted'
      # Show "Internal Use Only" page
      res.view = 'restricted_homepage'
    else
      # Show normal homepage
      res.view = 'homepage'
    end
  end
end
```

#### Otto Route Definitions

```ruby
# In routes configuration
router.define_routes do
  get '/', to: lambda { |req, res|
    if req.env['HTTP_X_ACCESS_MODE'] == 'restricted'
      res.status = 403
      res.body = render_template('internal_only.html.erb')
    else
      res.body = render_template('homepage.html.erb')
    end
  }
end
```

#### Request Helper Method (Optional)

Add convenience method to `Otto::RequestHelpers`:

```ruby
module Otto
  module RequestHelpers
    def access_restricted?
      env['HTTP_X_ACCESS_MODE'] == 'restricted'
    end

    def access_mode
      env['HTTP_X_ACCESS_MODE'] || 'normal'
    end
  end
end

# Usage in handlers
def index(req, res)
  return restricted_view if req.access_restricted?
  normal_view
end
```

## Security Considerations

### Trust Boundary

**CRITICAL**: This middleware assumes the application runs behind a trusted reverse proxy.

**Security requirements**:
- Trigger secret MUST be strong (32+ characters, random)
- Trigger secret MUST be shared only with trusted infrastructure
- Application MUST be inaccessible directly (only via proxy)
- Proxy MUST validate/sanitize `X-Forwarded-For` header

### Attack Vectors & Mitigations

| Attack | Mitigation |
|--------|------------|
| Client spoofs trigger header | Secret comparison fails → passthrough |
| Client spoofs X-Forwarded-For | Proxy should strip/validate this header |
| Timing attack on secret | Constant-time comparison (`secure_compare`) |
| CIDR enumeration | Log all denials, monitor for scanning patterns |

### Best Practices

1. **Rotate trigger secret periodically** (monthly/quarterly)
2. **Log all access control decisions** (audit trail)
3. **Monitor for abuse patterns** (rapid IP changes, scanning)
4. **Test in staging** before production deployment
5. **Document shared secret location** (secrets manager, KMS)

## Testing

### Manual Testing

```bash
# Test with internal IP (should allow)
curl -H "X-Access-Control-Trigger: your-secret" \
     -H "X-Forwarded-For: 10.0.0.1" \
     http://localhost:3000/

# Test with external IP (should restrict)
curl -H "X-Access-Control-Trigger: your-secret" \
     -H "X-Forwarded-For: 203.0.113.1" \
     http://localhost:3000/

# Test without trigger header (should passthrough)
curl -H "X-Forwarded-For: 203.0.113.1" \
     http://localhost:3000/

# Check mode header in response (for debugging)
curl -v -H "X-Access-Control-Trigger: your-secret" \
        -H "X-Forwarded-For: 10.0.0.1" \
        http://localhost:3000/ 2>&1 | grep -i x-access-mode
```

### Automated Testing

Run tryouts test suite:

```bash
bundle exec try --agent try/middleware/access_control_try.rb
```

## Operational Monitoring

### Metrics to Track

- **Access mode distribution**: Normal vs. restricted requests
- **CIDR match rate**: Percentage of IPs matching allowlist
- **Trigger activation rate**: How often access control evaluates
- **Denial patterns**: External IPs attempting access

### Logging Examples

```ruby
# In application code
logger.info(
  'Homepage access',
  access_mode: req.env['HTTP_X_ACCESS_MODE'],
  client_ip: req.env['HTTP_X_FORWARDED_FOR'],
  user_agent: req.env['HTTP_USER_AGENT']
)
```

### Alerts

Set up alerts for:
- High rate of restricted access attempts
- Trigger header with wrong secret (potential attack)
- Unusual IP patterns in allowlist matches

## Troubleshooting

### Mode header not being set

**Symptoms**: `env['HTTP_X_ACCESS_MODE']` is `nil`

**Causes**:
1. Middleware not enabled: Check `access_control.enabled` in config
2. Missing trigger header: Verify proxy sets header correctly
3. Secret mismatch: Ensure proxy secret matches config
4. Middleware order: Must be in stack before route handlers

**Debug**:
```bash
# Enable debug logging
export LOG_LEVEL=debug

# Check middleware logs
tail -f log/development.log | grep AccessControl
```

### All requests denied

**Symptoms**: All IPs get `restricted` mode

**Causes**:
1. Empty `allowed_cidrs`: No IPs in allowlist
2. CIDR syntax error: Invalid CIDR notation
3. IPv6 vs IPv4 mismatch: Client using IPv6, allowlist has IPv4

**Debug**:
```ruby
# In Rails console or debugging session
require 'ipaddr'

# Test CIDR matching
ip = IPAddr.new('10.0.0.1')
cidr = IPAddr.new('10.0.0.0/8')
cidr.include?(ip)  # Should return true
```

### Proxy header not forwarding

**Symptoms**: Middleware sees proxy IP instead of client IP

**Causes**:
1. Proxy not setting `X-Forwarded-For`
2. Application reading wrong IP source
3. Multiple proxies overwriting header

**Debug**:
```bash
# Log all headers
curl -v http://localhost:3000/ 2>&1 | grep -i forward
```

## Examples

### Use Case: Internal-Only Homepage

**Requirement**: Show full homepage to internal IPs, restricted page to external IPs.

**Setup**:

1. Configure Caddy:
```caddyfile
example.com {
    @homepage path /
    handle @homepage {
        header_up X-Access-Control-Trigger "shared-secret-123"
        reverse_proxy localhost:3000
    }
    reverse_proxy localhost:3000
}
```

2. Configure allowlist:
```bash
# Via environment variable
export ALLOWED_CIDRS="192.168.0.0/16,10.0.0.0/8"
```

3. Implement handler:
```ruby
def homepage(req, res)
  if req.env['HTTP_X_ACCESS_MODE'] == 'restricted'
    res.view = 'restricted_homepage'
    res.locals[:message] = 'Internal Use Only'
  else
    res.view = 'homepage'
  end
end
```

### Use Case: Per-Route Access Control

**Requirement**: Different routes have different access requirements.

**Setup**:

```caddyfile
example.com {
    # Public routes - no access control
    @public path /about /help /contact
    handle @public {
        reverse_proxy localhost:3000
    }

    # Protected routes - require internal IP
    @protected path /admin /dashboard
    handle @protected {
        header_up X-Access-Control-Trigger "admin-secret"
        reverse_proxy localhost:3000
    }

    # API routes - different secret
    @api path /api/*
    handle @api {
        header_up X-Access-Control-Trigger "api-secret"
        reverse_proxy localhost:3000
    }

    reverse_proxy localhost:3000
}
```

Note: Use different trigger secrets for different access policies, or implement multiple middleware instances.

## Maintenance

### Secret Rotation Procedure

1. Generate new secret: `openssl rand -base64 32`
2. Update proxy configuration with new secret
3. Reload proxy: `systemctl reload caddy` (or equivalent)
4. Update application config with new secret
5. Restart application
6. Verify with manual test
7. Monitor logs for secret mismatch errors (indicates missed configuration)

### CIDR Updates

To add/remove IP ranges:

1. Update `ALLOWED_CIDRS` environment variable with comma-separated CIDRs
2. Restart application (or reload config if hot-reload supported)
3. Test with IPs in new CIDR range
4. Monitor access logs for expected behavior

Example:
```bash
# Add new office subnet
export ALLOWED_CIDRS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,198.51.100.0/24"
```

## Related Documentation

- [Otto Request Lifecycle](../cheatsheet-otto-request-lifecycle.md)
- [IP Privacy System](../cheatsheet-otto-ip-privacy-patterns.md)
- [Middleware Architecture](../lib/middleware/README.md)
- [Security Configuration](../docs/SECURITY.md)

## Support

For issues or questions:
- Check logs: `tail -f log/development.log | grep AccessControl`
- Run tests: `bundle exec try --agent try/middleware/access_control_try.rb`
- Review configuration: `cat etc/access_control.yaml`
- Verify middleware stack: Check application initialization logs
