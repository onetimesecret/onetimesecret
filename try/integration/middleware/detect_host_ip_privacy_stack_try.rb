# try/integration/middleware/detect_host_ip_privacy_stack_try.rb
#
# frozen_string_literal: true

# These tryouts mount the REAL Otto::Security::Middleware::IPPrivacyMiddleware
# in front of Rack::DetectHost — the production ordering from
# lib/onetime/application/middleware_stack.rb — and drive requests through the
# combined stack.
#
# Purpose: pin the cross-gem contract that DetectHost depends on. DetectHost
# trusts forwarded host headers based on env['otto.via_trusted_proxy'], which
# otto records from the ORIGINAL connecting peer before rewriting REMOTE_ADDR
# to the resolved (masked) client IP. The detect_host_try.rb tryouts inject
# that key by hand, so they would keep passing if a future otto release
# renamed the key or stopped setting it — while production silently regressed
# to the private_ip?(REMOTE_ADDR) fallback and re-broke every custom domain
# (the 2026-08-05 TRUSTED_PROXY_ENABLED incident). These tests fail instead.
#
# We're testing:
# 1. otto still records env['otto.via_trusted_proxy'] (contract pin)
# 2. The incident shape: trusted proxy peer + public visitor in XFF ->
#    REMOTE_ADDR rewritten to a public IP, forwarded host headers still trusted
# 3. Direct public request: forwarded host headers ignored, Host wins
# 4. Direct-connect config (no trusted proxies): forwarded host headers ignored

require_relative '../../support/test_helpers'

require 'logger'
require 'stringio'
require 'otto'

require 'middleware/detect_host'

@logger = Logger.new(StringIO.new)

# Capture the env DetectHost's downstream app receives, so assertions can see
# both the detected host and the post-otto REMOTE_ADDR.
@captured = nil
@capture_app = lambda do |env|
  @captured = env
  [200, {}, ['OK']]
end

# Mirror the production filter-mode config built by
# MiddlewareStack.ip_privacy_security_config: private ranges trusted as
# proxies, private/localhost masking on.
@trusted_config = Otto::Security::Config.new
@trusted_config.ip_privacy_config.mask_private_ips = true
@trusted_config.add_trusted_proxy('10.0.0.0/8')

@trusted_stack = Otto::Security::Middleware::IPPrivacyMiddleware.new(
  Rack::DetectHost.new(@capture_app, logger: @logger),
  @trusted_config,
)

# Direct-connect config: masking on, no trusted proxies (the default returned
# by ip_privacy_security_config when site.network.trusted_proxy is disabled).
@direct_config = Otto::Security::Config.new
@direct_config.ip_privacy_config.mask_private_ips = true

@direct_stack = Otto::Security::Middleware::IPPrivacyMiddleware.new(
  Rack::DetectHost.new(@capture_app, logger: @logger),
  @direct_config,
)

## Contract pin: otto records otto.via_trusted_proxy for downstream consumers.
## If an otto upgrade renames or drops this key, DetectHost silently falls
## back to the private_ip? heuristic — fail here instead.
@trusted_stack.call({
  'REMOTE_ADDR' => '10.0.0.5',
  'HTTP_X_FORWARDED_FOR' => '203.0.113.50',
  'HTTP_HOST' => 'eu.onetimesecret.com',
})
[@captured.key?('otto.via_trusted_proxy'), @captured['otto.via_trusted_proxy']]
#=> [true, true]

## Incident shape (2026-08-05): request arrives via trusted proxy (10.0.0.5)
## carrying the public visitor in X-Forwarded-For and the customer domain in
## Apx-Incoming-Host. Otto resolves and rewrites REMOTE_ADDR to the (masked)
## PUBLIC visitor IP before DetectHost runs — the old private_ip?(REMOTE_ADDR)
## gate failed here and every custom domain fell back to canonical. The
## forwarded host header must survive the rewrite.
@trusted_stack.call({
  'REMOTE_ADDR' => '10.0.0.5',
  'HTTP_X_FORWARDED_FOR' => '203.0.113.50',
  'HTTP_APX_INCOMING_HOST' => 'ca.metalbaum.example.com',
  'HTTP_HOST' => 'eu.onetimesecret.com',
})
[
  @captured['rack.detected_host'],
  Rack::DetectHost.private_ip?(@captured['REMOTE_ADDR']),
]
#=> ['ca.metalbaum.example.com', false]

## Spoofing still blocked: a direct public client sending forged forwarded
## host headers gets only its Host header honored, and the trust flag is false.
@trusted_stack.call({
  'REMOTE_ADDR' => '198.51.100.7',
  'HTTP_APX_INCOMING_HOST' => 'spoofed.example.com',
  'HTTP_X_FORWARDED_HOST' => 'also-spoofed.example.com',
  'HTTP_HOST' => 'eu.onetimesecret.com',
})
[@captured['rack.detected_host'], @captured['otto.via_trusted_proxy']]
#=> ['eu.onetimesecret.com', false]

## Direct-connect deployment (no trusted proxies configured): even a private
## peer gets no forwarded-host trust — the recorded decision (empty CIDR list)
## overrides the old any-RFC-1918-peer heuristic.
@direct_stack.call({
  'REMOTE_ADDR' => '10.0.0.5',
  'HTTP_X_FORWARDED_HOST' => 'spoofed.example.com',
  'HTTP_HOST' => 'eu.onetimesecret.com',
})
[@captured['rack.detected_host'], @captured['otto.via_trusted_proxy']]
#=> ['eu.onetimesecret.com', false]
