#!/usr/bin/env ruby
# scripts/ip_privacy_trusted_proxy_repro.rb
#
# Reference reproduction for #3427 — "IP privacy middleware hides the real
# client IP when running behind a proxy" — kept for the trusted-proxy
# harmonization follow-up.
#
# Models the two Otto IPPrivacyMiddleware instances onetime stacks in series:
#   - outer: onetime's universal MiddlewareStack mount (today: no security config)
#   - inner: the Otto router's own middleware (mask_private_ips via
#            enable_full_ip_privacy!, empty trusted-proxy list)
#
# Shows the broken behaviour (private ingress hop masked to .0, real client
# destroyed) vs the PR #3429 fix (real client resolved first, then masked to
# its own /24).
#
# Run:  ruby scripts/ip_privacy_trusted_proxy_repro.rb   (requires otto 2.2.0)
#
# Caveats: it reaches into @ip_privacy_config to mimic enable_full_ip_privacy!
# without booting a full router, and models the two middlewares directly rather
# than the real Rack builder — a faithful model of the otto code path, not a
# full onetime integration test.

require 'otto'

# The PR #3429 regexp (RFC1918 / loopback / link-local / IPv6 ULA+loopback)
PRIVATE_PROXY_RANGES = %r{
  \A(?:
    10\.|
    127\.|
    192\.168\.|
    169\.254\.|
    172\.(?:1[6-9]|2\d|3[01])\.|
    ::1\z|
    f[cd]
  )
}ix

IPPM = Otto::Security::Middleware::IPPrivacyMiddleware

# Inner middleware = the Otto ROUTER's own IPPrivacyMiddleware.
# core/application.rb calls router.enable_full_ip_privacy! => mask_private_ips = true,
# and Otto.new(routes_path) is called WITHOUT trusted_proxies => empty trusted list.
def router_security_config
  cfg = Otto::Security::Config.new
  cfg.instance_variable_get(:@ip_privacy_config).mask_private_ips = true
  cfg # trusted_proxies stays []
end

# Outer middleware = onetime's universal MiddlewareStack mount.
def outer_config_broken = nil                       # builder.use IPPM            (today)
def outer_config_fixed                              # builder.use IPPM, <cfg>     (PR #3429)
  cfg = Otto::Security::Config.new
  cfg.add_trusted_proxy(PRIVATE_PROXY_RANGES)
  cfg
end

# Terminal app: capture what downstream actually sees.
terminal = ->(env) {
  $seen = { 'REMOTE_ADDR' => env['REMOTE_ADDR'], 'XFF' => env['HTTP_X_FORWARDED_FOR'] }
  [200, {}, ['ok']]
}

def fresh_env
  { 'REMOTE_ADDR' => '10.244.10.5',                 # Traefik ingress pod (RFC1918)
    'HTTP_X_FORWARDED_FOR' => '203.0.113.42',        # the real visitor
    'HTTP_USER_AGENT' => 'curl/8', 'rack.input' => StringIO.new }
end

def run(outer_cfg, terminal)
  inner = IPPM.new(terminal, router_security_config) # router's middleware (mask_private_ips=true)
  outer = IPPM.new(inner, outer_cfg)                 # universal middleware (outermost, runs first)
  outer.call(fresh_env)
end

require 'stringio'
run(outer_config_broken, terminal)
puts "BROKEN (outer mounted with NO config):  downstream sees #{$seen.inspect}"
run(outer_config_fixed, terminal)
puts "FIXED  (outer mounted WITH PR #3429 cfg): downstream sees #{$seen.inspect}"

# Sanity: the PR's trusted_proxy? matching
c = outer_config_fixed
puts
puts "trusted_proxy?('10.244.10.5')  => #{c.trusted_proxy?('10.244.10.5')}   (ingress hop, should trust)"
puts "trusted_proxy?('203.0.113.42') => #{c.trusted_proxy?('203.0.113.42')}  (real client, should NOT trust)"
