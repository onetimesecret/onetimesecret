# try/unit/http/guard_try.rb
#
# frozen_string_literal: true

# Unit coverage for Onetime::Http::Guard, the shared SSRF egress guard that
# unifies the SafeFetch, SsoConfig::SsrfProtection, and DispatchNotification
# blocklists into one deny-by-default, fail-closed range set.
#
# Hermetic: DNS (Resolv) is stubbed by redefining the module_function seam
# Guard.resolve_addresses (internal callers dispatch through the module
# singleton, so the redefinition covers resolve_and_validate! too). NO real
# network is touched and no OT.boot! / Redis / encryption is required
# (requiring 'onetime' through the support helper is enough to define
# Onetime::Problem, the error base).
#
# Proves: the UNION blocklist (incl. Teredo 2001::/32, which SafeFetch
# lacked), v4-mapped AND v4-compatible unwrapping, zero-address guard,
# fail-closed on unparseable/encoded addresses and mixed RRsets, empty
# resolution rejected, IP-literal hosts validated directly (Resolv::DNS
# returns [] for literals), IPv4-first uniq'd ordering, and pinned_address!.
#
# Run:
#   bundle exec try --agent try/unit/http/guard_try.rb

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/http/guard'

G = Onetime::Http::Guard

# Stub DNS: host => [ip strings]. Unknown hosts resolve to [] (which is also
# what Resolv::DNS#getaddresses returns for IP-literal input, so the literal
# fallback branch is exercised for free).
GUARD_DNS = {
  'ok.test'   => ['93.184.216.34'],
  'mix.test'  => ['93.184.216.34', '127.0.0.1'], # split RRset: one public, one loopback
  'ds.test'   => ['2606:4700::6810:84e5', '8.8.8.8', '93.184.216.34', '8.8.8.8'],
  'nx.test'   => [],
  'meta.test' => ['169.254.169.254'],
}.freeze

def G.resolve_addresses(host)
  GUARD_DNS.fetch(host) { [] }
end

# Classify what resolve_and_validate!/pinned_address! raises.
def classify
  yield
  :no_raise
rescue G::Blocked
  :blocked
rescue StandardError => ex
  "unexpected:#{ex.class}"
end

## Blocked subclasses Onetime::Problem (same pattern as SafeFetch::Error)
G::Blocked < Onetime::Problem
#=> true

## Every forbidden v4/v6 target is blocked: loopback, RFC1918, metadata,
## unspecified (both spellings), this-network, CGNAT, IETF, benchmarking,
## reserved, broadcast, multicast, v6 loopback/unspecified, v4-compat,
## v4-mapped IMDS, NAT64, 6to4, Teredo, doc range, link-local, ULA, v6 multicast
%w[
  127.0.0.1 10.0.0.1 169.254.169.254 0.0.0.0 0.1.2.3 100.64.0.1 192.0.0.1
  198.18.0.1 240.0.0.1 255.255.255.255 224.0.0.1 172.16.0.1 192.168.1.1
  ::1 :: ::127.0.0.1 ::ffff:169.254.169.254 64:ff9b::a9fe:a9fe
  64:ff9b:1::a9fe:a9fe 2002:7f00:0001:: 2001:0:abcd::1 2001:db8::1
  fe80::1 fc00::1 ff02::1
].reject { |addr| G.blocked_ip?(addr) }
#=> []

## Teredo (2001::/32) is blocked — the range SafeFetch's own list lacked
G.blocked_ip?('2001:0000:4136:e378:8000:63bf:3fff:fdd2')
#=> true

## ::0.0.0.0 spelling of the unspecified address is blocked (to_i.zero? guard)
G.blocked_ip?('::0.0.0.0')
#=> true

## Encoded-loopback smuggling (decimal/hex) fails closed as blocked
['2130706433', '0x7f000001', 'not-an-ip', ''].map { |addr| G.blocked_ip?(addr) }
#=> [true, true, true, true]

## Accepts IPAddr instances as well as Strings
[G.blocked_ip?(IPAddr.new('127.0.0.1')), G.blocked_ip?(IPAddr.new('8.8.8.8'))]
#=> [true, false]

## Public addresses pass the guard (v4 and v6)
%w[93.184.216.34 8.8.8.8 2606:4700::6810:84e5].select { |addr| G.blocked_ip?(addr) }
#=> []

## resolve_and_validate! returns the validated addresses for a clean host
G.resolve_and_validate!('ok.test')
#=> ['93.184.216.34']

## Fail-closed: a mixed RRset (one public + one loopback) raises Blocked
classify { G.resolve_and_validate!('mix.test') }
#=> :blocked

## A host resolving only to the metadata service raises Blocked
classify { G.resolve_and_validate!('meta.test') }
#=> :blocked

## Empty resolution raises Blocked (nothing resolvable, nothing fetchable)
classify { G.resolve_and_validate!('nx.test') }
#=> :blocked

## Addresses come back uniq'd and IPv4-first (AAAA listed first in the RRset)
G.resolve_and_validate!('ds.test')
#=> ['8.8.8.8', '93.184.216.34', '2606:4700::6810:84e5']

## IP-literal host: Resolv::DNS resolves literals to [], so the literal is
## validated directly and returned as-is
G.resolve_and_validate!('93.184.216.34')
#=> ['93.184.216.34']

## IP-literal v6 host passes through the same branch
G.resolve_and_validate!('2606:4700::6810:84e5')
#=> ['2606:4700::6810:84e5']

## A blocked IP literal raises Blocked, not "no A/AAAA records"
begin
  G.resolve_and_validate!('169.254.169.254')
rescue G::Blocked => ex
  ex.message
end
#=> 'blocked address 169.254.169.254 for 169.254.169.254'

## An unresolvable non-IP host still reports empty resolution
begin
  G.resolve_and_validate!('unknown.test')
rescue G::Blocked => ex
  ex.message
end
#=> 'no A/AAAA records for unknown.test'

## pinned_address! returns the first validated address (IPv4 preferred)
G.pinned_address!('ds.test')
#=> '8.8.8.8'

## pinned_address! propagates Blocked for a forbidden target
classify { G.pinned_address!('meta.test') }
#=> :blocked
