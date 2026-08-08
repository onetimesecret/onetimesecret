# try/integration/middleware/detect_host_ip_privacy_stack_try.rb
#
# frozen_string_literal: true

# These tryouts mount the REAL Otto::Security::Middleware::IPPrivacyMiddleware
# in front of Rack::DetectHost — the production ordering from
# lib/onetime/application/middleware_stack.rb — and drive requests through the
# combined stack, with the security config built by the PRODUCTION builder
# (MiddlewareStack.ip_privacy_security_config) so config-construction drift is
# covered too, not just the middleware contract.
#
# Purpose: pin the cross-gem contract that DetectHost depends on. DetectHost
# trusts forwarded host headers when EITHER env['otto.via_trusted_proxy'] is
# true (recorded by otto from the ORIGINAL connecting peer before it rewrites
# REMOTE_ADDR to the resolved/masked client IP) OR REMOTE_ADDR is private
# (legacy heuristic). The detect_host_try.rb tryouts inject the otto key by
# hand, so they would keep passing if a future otto release renamed the key or
# stopped setting it — while production silently regressed to the
# private_ip?(REMOTE_ADDR) fallback and re-broke every custom domain (the
# 2026-08-05 TRUSTED_PROXY_ENABLED incident). These tests fail instead.
#
# We're testing:
# 1. The key-name contract: Otto::EnvKeys::VIA_TRUSTED_PROXY still equals
#    Rack::DetectHost::VIA_TRUSTED_PROXY_KEY (catches otto key renames)
# 2. otto still records env['otto.via_trusted_proxy'] (contract pin)
# 3. The incident shape: trusted proxy peer + public visitor in XFF ->
#    REMOTE_ADDR rewritten to a public IP, forwarded host headers still trusted
# 4. Direct public request: forwarded host headers ignored, Host wins
# 5. Direct-connect config + private peer: forwarded host headers trusted via
#    the private-peer heuristic (back-compat for self-hosted installs)
# 6. Depth mode: otto records peer trust from the depth assertion (otto#226),
#    so forwarded host headers are honored via the otto key alone

require_relative '../../support/test_helpers'

require 'logger'
require 'stringio'
require 'otto'
# Documentation-only module: NOT loaded by `require 'otto'`, must be explicit.
require 'otto/env_keys'

require 'middleware/detect_host'
require 'onetime/application/middleware_stack'

@logger = Logger.new(StringIO.new)

# Capture the env DetectHost's downstream app receives, so assertions can see
# both the detected host and the post-otto REMOTE_ADDR.
@captured    = nil
@capture_app = ->(env) do
  @captured = env
  [200, {}, ['OK']]
end

# Build every security config through the PRODUCTION builder,
# MiddlewareStack.ip_privacy_security_config — the single source of truth
# that translates site.network.trusted_proxy YAML into Otto::Security::Config
# (PRIVATE_PROXY_RANGES in filter mode, the depth+1 remap in depth mode,
# mask_private_ips always). A hand-built config here could not catch
# config-construction drift; see also
# spec/unit/onetime/application/ip_privacy_parity_spec.rb.
#
# The builder reads only OT.conf['site']['network']['trusted_proxy'], so a
# minimal conf hash suffices (no full boot / defaults load needed). OT is not
# booted in this tryout (OT.conf is nil), so swap a purpose-built hash in via
# the private conf= writer and restore afterwards — all builds happen here in
# setup, before any test case runs, so nothing leaks between cases.
@saved_conf              = OT.conf
@build_production_config = ->(trusted_proxy) do
  OT.send(:conf=, { 'site' => { 'network' => { 'trusted_proxy' => trusted_proxy } } })
  Onetime::Application::MiddlewareStack.ip_privacy_security_config
end

# Filter mode (the incident config): PRIVATE_PROXY_RANGES trusted as proxies.
@trusted_config = @build_production_config.call('enabled' => true, 'mode' => 'filter')

# Depth mode: count-based, Onetime depth 1 => otto trusted_proxy_depth 2.
# Depth and CIDRs are mutually exclusive in otto (it raises if both are set).
@depth_config = @build_production_config.call('enabled' => true, 'mode' => 'depth', 'depth' => 1)

# Direct-connect: trusted_proxy disabled — masking on, empty proxy trust list.
@direct_config = @build_production_config.call('enabled' => false)

OT.send(:conf=, @saved_conf)

@trusted_stack = Otto::Security::Middleware::IPPrivacyMiddleware.new(
  Rack::DetectHost.new(@capture_app, logger: @logger),
  @trusted_config,
)

@depth_stack = Otto::Security::Middleware::IPPrivacyMiddleware.new(
  Rack::DetectHost.new(@capture_app, logger: @logger),
  @depth_config,
)

@direct_stack = Otto::Security::Middleware::IPPrivacyMiddleware.new(
  Rack::DetectHost.new(@capture_app, logger: @logger),
  @direct_config,
)

## Key-name contract pin: DetectHost carries its own frozen literal (to stay
## otto-agnostic) that must mirror otto's documented env key
## (Otto::EnvKeys::VIA_TRUSTED_PROXY). If an otto upgrade renames the key,
## this fails loudly instead of DetectHost silently never seeing the trust
## signal. (Pinned as a value pair, not a bare `==`, so rubocop's Lint/Void
## autocorrect cannot delete the expression.)
[Otto::EnvKeys::VIA_TRUSTED_PROXY, Rack::DetectHost::VIA_TRUSTED_PROXY_KEY]
#=> ['otto.via_trusted_proxy', 'otto.via_trusted_proxy']

## Contract pin: otto records otto.via_trusted_proxy for downstream consumers.
## If an otto upgrade stops setting this key, DetectHost silently falls back
## to the private_ip? heuristic — fail here instead.
@trusted_stack.call(
  {
    'REMOTE_ADDR' => '10.0.0.5',
    'HTTP_X_FORWARDED_FOR' => '203.0.113.50',
    'HTTP_HOST' => 'eu.onetimesecret.com',
  },
)
[@captured.key?('otto.via_trusted_proxy'), @captured['otto.via_trusted_proxy']]
#=> [true, true]

## Incident shape (2026-08-05): request arrives via trusted proxy (10.0.0.5)
## carrying the public visitor in X-Forwarded-For and the customer domain in
## Apx-Incoming-Host. Otto resolves and rewrites REMOTE_ADDR to the (masked)
## PUBLIC visitor IP before DetectHost runs — the old private_ip?(REMOTE_ADDR)
## gate failed here and every custom domain fell back to canonical. The
## forwarded host header must survive the rewrite.
@trusted_stack.call(
  {
    'REMOTE_ADDR' => '10.0.0.5',
    'HTTP_X_FORWARDED_FOR' => '203.0.113.50',
    'HTTP_APX_INCOMING_HOST' => 'ca.metalbaum.example.com',
    'HTTP_HOST' => 'eu.onetimesecret.com',
  },
)
[
  @captured['rack.detected_host'],
  Rack::DetectHost.private_ip?(@captured['REMOTE_ADDR']),
]
#=> ['ca.metalbaum.example.com', false]

## Spoofing still blocked (the security invariant): a direct public client
## sending forged forwarded host headers gets only its Host header honored,
## and the trust flag is false.
@trusted_stack.call(
  {
    'REMOTE_ADDR' => '198.51.100.7',
    'HTTP_APX_INCOMING_HOST' => 'spoofed.example.com',
    'HTTP_X_FORWARDED_HOST' => 'also-spoofed.example.com',
    'HTTP_HOST' => 'eu.onetimesecret.com',
  },
)
[@captured['rack.detected_host'], @captured['otto.via_trusted_proxy']]
#=> ['eu.onetimesecret.com', false]

## Direct-connect deployment (no trusted proxies configured): a private peer
## still gets forwarded-host trust. Otto records via_trusted_proxy=false (its
## trust list is empty), but the masked REMOTE_ADDR (10.0.0.0) stays private,
## so DetectHost's private-peer heuristic grants trust — the false key never
## revokes it. This pins pre-incident back-compat for default-config
## self-hosted installs behind a local reverse proxy (nginx/Caddy on the same
## box or LAN), which never declare site.network.trusted_proxy.
@direct_stack.call(
  {
    'REMOTE_ADDR' => '10.0.0.5',
    'HTTP_X_FORWARDED_HOST' => 'forwarded.example.com',
    'HTTP_HOST' => 'eu.onetimesecret.com',
  },
)
[@captured['rack.detected_host'], @captured['otto.via_trusted_proxy']]
#=> ['forwarded.example.com', false]

## Depth mode grants forwarded-host trust (otto#226 — the deliberate flip of
## the KNOWN LIMITATION this case used to pin): depth and CIDRs are mutually
## exclusive so otto's matcher list is empty, but configuring a depth asserts
## the connecting peer is the proxy tier, so otto records
## via_trusted_proxy=true from the pre-rewrite peer. REMOTE_ADDR is still
## rewritten to the (masked) PUBLIC client, so the private-peer heuristic
## still declines — the otto key is the ONLY trust signal here, which is
## exactly the cross-gem contract this file exists to pin.
##
## The two-entry XFF is load-bearing: otto's depth chain is XFF + REMOTE_ADDR
## and this config trusts depth 2 (ots depth 1 + the otto#151 remap), so a
## single-entry XFF would leave the chain too short — otto would fall back to
## REMOTE_ADDR (10.0.0.5, private), the private-peer heuristic would grant
## trust, and the otto-key-only assertion would silently weaken. Do NOT
## "align" this XFF with the single-entry filter-mode case above.
@depth_stack.call(
  {
    'REMOTE_ADDR' => '10.0.0.5',
    'HTTP_X_FORWARDED_FOR' => '203.0.113.50, 10.0.0.5',
    'HTTP_APX_INCOMING_HOST' => 'ca.metalbaum.example.com',
    'HTTP_HOST' => 'eu.onetimesecret.com',
  },
)
[
  @captured['rack.detected_host'],
  @captured['otto.via_trusted_proxy'],
  Rack::DetectHost.private_ip?(@captured['REMOTE_ADDR']),
]
#=> ['ca.metalbaum.example.com', true, false]
