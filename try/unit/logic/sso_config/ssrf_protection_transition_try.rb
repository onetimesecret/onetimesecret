# try/unit/logic/sso_config/ssrf_protection_transition_try.rb
#
# frozen_string_literal: true

# Regression tests for the IPv6 transition-address SSRF bypass.
#
# Background: SsrfProtection guards SSO issuer URLs before OmniAuth OIDC
# discovery fetches metadata from them. The original guard checked only
# IPAddr#loopback?, #private?, and #link_local?, which match native IPv4/IPv6
# ranges only. IPv4 addresses embedded in IPv6 transition formats
# (IPv4-mapped, NAT64, 6to4, Teredo) therefore passed the guard and could
# point OmniAuth at loopback, the cloud metadata service (169.254.169.254),
# or private networks.
#
# The range checks themselves now live in Onetime::Http::Guard (the shared
# SSRF egress guard); SsrfProtection#blocked_ip? is a thin delegation. These
# vectors stay as regression coverage that the delegation preserves the
# original blocking behavior, plus the ranges Guard added on top (multicast,
# v6 documentation) and Guard's fail-closed handling of unparseable input.
#
# These tests exercise the validation methods directly with literal IPs, so
# they are hermetic: no HTTP and no DNS. DNS resolution is stubbed in setup
# so resolves_to_internal_ip? cannot reach the network.
#
# Run:
#   try try/unit/logic/sso_config/ssrf_protection_transition_try.rb --agent

require 'ipaddr'
require 'resolv'
require_relative '../../../../lib/onetime/errors'
require_relative '../../../../lib/onetime/http/guard'
require_relative '../../../../apps/api/domains/logic/sso_config/ssrf_protection'

# Stub DNS: known hosts resolve to fixed answers, everything else (including
# literal-IP hosts) returns [] meaning "no resolved addresses". Defined on the
# ::Resolv singleton (tryouts evaluates files inside a sandbox module, so a
# bare `class Resolv` reopening would create a sandboxed twin, not stub the
# real class SsrfProtection calls).
ssrf_try_dns = {
  'garbage-answer.test' => ['not-an-ip-address'],       # unparseable resolver answer
  'mixed-garbage.test'  => ['93.184.216.34', 'bogus!'], # one good, one unparseable
}.freeze
::Resolv.define_singleton_method(:getaddresses) do |hostname|
  ssrf_try_dns.fetch(hostname) { [] }
end

@validator = Object.new
@validator.extend(DomainsAPI::Logic::SsoConfig::SsrfProtection)

## Sanity: a normal public HTTPS issuer is accepted
@validator.valid_issuer_host?('https://idp.example.com')
#=> true

## Sanity: native IPv4 loopback is still blocked
@validator.valid_issuer_host?('https://127.0.0.1')
#=> false

## Sanity: native IPv6 loopback is still blocked
@validator.valid_issuer_host?('https://[::1]')
#=> false

## Sanity: native IPv6 ULA (private) is still blocked
@validator.valid_issuer_host?('https://[fc00::1]')
#=> false

## BYPASS: IPv4-mapped IPv6 loopback (::ffff:127.0.0.1, hex form) is blocked
@validator.valid_issuer_host?('https://[::ffff:7f00:1]')
#=> false

## BYPASS: IPv4-mapped IPv6 cloud IMDS (::ffff:169.254.169.254) is blocked
@validator.valid_issuer_host?('https://[::ffff:a9fe:a9fe]')
#=> false

## BYPASS: IPv4-mapped dotted form (::ffff:169.254.169.254) is blocked
@validator.valid_issuer_host?('https://[::ffff:169.254.169.254]')
#=> false

## BYPASS: IPv4-mapped private 10.0.0.1 (::ffff:10.0.0.1) is blocked
@validator.valid_issuer_host?('https://[::ffff:a00:1]')
#=> false

## BYPASS: IPv4-compatible IPv6 cloud IMDS (::169.254.169.254) is blocked
@validator.valid_issuer_host?('https://[::169.254.169.254]')
#=> false

## BYPASS: IPv4-compatible IPv6 loopback (::127.0.0.1) is blocked
@validator.valid_issuer_host?('https://[::127.0.0.1]')
#=> false

## BYPASS: IPv4-compatible private 10.0.0.1 (::10.0.0.1) is blocked
@validator.valid_issuer_host?('https://[::10.0.0.1]')
#=> false

## blocked_ip? unwraps IPv4-compatible and matches the embedded IPv4
@validator.blocked_ip?(IPAddr.new('::169.254.169.254'))
#=> true

## BYPASS: NAT64 well-known prefix to IMDS (64:ff9b::169.254.169.254) is blocked
@validator.valid_issuer_host?('https://[64:ff9b::a9fe:a9fe]')
#=> false

## BYPASS: NAT64 well-known prefix to loopback (64:ff9b::127.0.0.1) is blocked
@validator.valid_issuer_host?('https://[64:ff9b::7f00:1]')
#=> false

## BYPASS: NAT64 local-use prefix (64:ff9b:1::/48) is blocked
@validator.valid_issuer_host?('https://[64:ff9b:1::a9fe:a9fe]')
#=> false

## BYPASS: 6to4 to loopback (2002:7f00:1::) is blocked
@validator.valid_issuer_host?('https://[2002:7f00:1::]')
#=> false

## BYPASS: 6to4 to IMDS (2002:a9fe:a9fe::) is blocked
@validator.valid_issuer_host?('https://[2002:a9fe:a9fe::]')
#=> false

## BYPASS: Teredo prefix (2001:0000::/32) is blocked
@validator.valid_issuer_host?('https://[2001:0000:4136:e378:8000:63bf:3fff:fdd2]')
#=> false

## internal_host? blocks IPv4-mapped IMDS at the method level
@validator.internal_host?('::ffff:a9fe:a9fe')
#=> true

## internal_host? blocks NAT64 IMDS at the method level
@validator.internal_host?('64:ff9b::a9fe:a9fe')
#=> true

## blocked_ip? unwraps IPv4-mapped and matches the embedded IPv4
@validator.blocked_ip?(IPAddr.new('::ffff:a9fe:a9fe'))
#=> true

## blocked_ip? matches a NAT64 address via the transition prefix list
@validator.blocked_ip?(IPAddr.new('64:ff9b::a00:1'))
#=> true

## BYPASS: unspecified IPv4 0.0.0.0 (routes to localhost) is blocked
@validator.valid_issuer_host?('https://0.0.0.0')
#=> false

## BYPASS: unspecified IPv6 [::] (routes to localhost) is blocked
@validator.valid_issuer_host?('https://[::]')
#=> false

## BYPASS: ::0.0.0.0 spelling of the unspecified address is blocked
@validator.blocked_ip?(IPAddr.new('::0.0.0.0'))
#=> true

## BYPASS: this-network 0.0.0.0/8 (0.0.0.5) is blocked
@validator.blocked_ip?(IPAddr.new('0.0.0.5'))
#=> true

## BYPASS: CGNAT shared range 100.64.0.0/10 is blocked
@validator.blocked_ip?(IPAddr.new('100.64.0.1'))
#=> true

## BYPASS: reserved 240.0.0.0/4 is blocked
@validator.blocked_ip?(IPAddr.new('240.0.0.1'))
#=> true

## BYPASS: broadcast 255.255.255.255 is blocked
@validator.blocked_ip?(IPAddr.new('255.255.255.255'))
#=> true

## NEWLY BLOCKED via Guard: IPv6 multicast ff00::/8 (ff02::1) is blocked
@validator.blocked_ip?(IPAddr.new('ff02::1'))
#=> true

## NEWLY BLOCKED via Guard: IPv6 documentation 2001:db8::/32 is blocked
@validator.blocked_ip?(IPAddr.new('2001:db8::1'))
#=> true

## NEWLY BLOCKED via Guard: IPv4 multicast 224.0.0.0/4 is blocked
@validator.blocked_ip?(IPAddr.new('224.0.0.1'))
#=> true

## blocked_ip? accepts String input (delegation to Guard preserves both forms)
@validator.blocked_ip?('127.0.0.1')
#=> true

## FAIL-CLOSED delta: blocked_ip? on unparseable input returns true (blocked);
## the pre-delegation code was IPAddr-only and callers rescued the parse error
## with false (skip). Guard treats unparseable as a forbidden target.
@validator.blocked_ip?('not-an-ip-address')
#=> true

## FAIL-CLOSED delta: a resolver answer we cannot parse now BLOCKS the host
## (previously resolves_to_internal_ip? skipped malformed addresses => false)
@validator.resolves_to_internal_ip?('garbage-answer.test')
#=> true

## FAIL-CLOSED delta: one good address plus one unparseable answer still blocks
@validator.resolves_to_internal_ip?('mixed-garbage.test')
#=> true

## blocked_ip? leaves a normal public IPv6 address alone
@validator.blocked_ip?(IPAddr.new('2606:4700:4700::1111'))
#=> false

## blocked_ip? leaves a normal public IPv4 address alone
@validator.blocked_ip?(IPAddr.new('93.184.216.34'))
#=> false

## blocked_ip? leaves another public IPv4 (8.8.8.8) alone
@validator.blocked_ip?(IPAddr.new('8.8.8.8'))
#=> false
