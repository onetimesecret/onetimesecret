# try/unit/security/create_account_rate_limiter_try.rb
#
# frozen_string_literal: true

# #3948 (audit 2026-07-30 finding #4): CreateAccountRateLimiter caps
# unauthenticated account creation, which previously had no limiter at all —
# one Customer record (no TTL) plus one welcome email per distinct address,
# with subaddressing folding many addresses onto one mailbox.
#
# Single tier, keyed on the client IP alone. Unlike ResetRequestRateLimiter
# there is no per-email backstop and there cannot be one: every request in the
# abuse pattern carries a FRESH address, so a per-email tier would mint one
# bucket per request and cap nothing.
#
# We test:
# 1. Under-limit requests are allowed; key shape and TTL
# 2. Over-limit raises LimitExceeded with the configured cap + lockout state
# 3. The limiter NEVER keys on the submitted address (enumeration safety)
# 4. nil/empty IP skips rather than sharing one global bucket
# 5. Cap-hit writes exactly one AdminAuditEvent, in the SECURITY trail, and
#    denied requests write no further ones
# 6. Garbage/non-positive config falls back to defaults instead of inverting
# 7. Configured-off (enabled:false) is a total no-op
# 8. The collapsed-IP operator hint is present and WIRED IN to the log line

require_relative '../../support/test_models'
require 'onetime/security/create_account_rate_limiter'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

# Enable the limiter with small, known caps (test config ships it disabled).
def set_create_account_rate_limit(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['authentication'] ||= {}
  new_conf['site']['authentication']['create_account_rate_limit'] = cfg
  OT.send(:conf=, new_conf)
end

# Toggle site.network.trusted_proxy.enabled for the collapsed-IP hint cases;
# the teardown restores @saved_conf wholesale.
def set_trusted_proxy_enabled(value)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['network'] ||= {}
  new_conf['site']['network']['trusted_proxy'] = value.nil? ? {} : { 'enabled' => value }
  OT.send(:conf=, new_conf)
end

set_create_account_rate_limit(
  'enabled' => true,
  'max_per_ip' => 3,
  'window' => 900,
  'lockout' => 900,
)

class CreateAccountRateLimiterTester
  include Onetime::Security::CreateAccountRateLimiter
end

@tester = CreateAccountRateLimiterTester.new
@redis  = Onetime::Customer.dbclient

@ip_a = '203.0.113.10'
@ip_b = '198.51.100.20'
@tag  = "#{Familia.now.to_i}_#{rand(10_000)}"

# true if a single enforce call raises LimitExceeded, false otherwise.
@raises = lambda do |ip|
  @tester.enforce_create_account_rate_limit!(ip)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, ip)
  redis.del("create_account:attempts:ip:#{ip}", "create_account:locked:ip:#{ip}")
end

cleanup(@redis, @ip_a)
cleanup(@redis, @ip_b)

## -- Under-limit ----------------------------------------------------------

## A single signup under the cap is allowed
@raises.call(@ip_a)
#=> false

## The attempts counter uses the documented key shape (the one the ratelimit
## Registry and the bin/ots CLI emit commands for)
@redis.exists?("create_account:attempts:ip:#{@ip_a}")
#=> true

## The counter carries a TTL within the configured window
ttl = @redis.ttl("create_account:attempts:ip:#{@ip_a}")
ttl.positive? && ttl <= 900
#=> true

## -- Enumeration safety ---------------------------------------------------

## The limiter keys ONLY on the IP: no key anywhere carries the submitted
## address. CreateAccount's whole response contract is that existing and new
## accounts are byte-identical, so an address-derived key would punch a hole
## straight through it. Two signups from one IP for two different addresses
## share one bucket and mint no address-keyed key.
@tester.enforce_create_account_rate_limit!(@ip_b)
[@redis.get("create_account:attempts:ip:#{@ip_b}").to_i,
 @redis.keys('create_account:*@*').length]
#=> [1, 0]

## -- Over-limit (cap = 3) -------------------------------------------------

## Two more requests reach the cap (total 3) and lock the tier
[@raises.call(@ip_a), @raises.call(@ip_a)]
#=> [false, false]

## The lockout key is now set
@redis.exists?("create_account:locked:ip:#{@ip_a}")
#=> true

## The attempts counter is cleared once the tier locks
@redis.exists?("create_account:attempts:ip:#{@ip_a}")
#=> false

## The next signup from that IP raises LimitExceeded
@raises.call(@ip_a)
#=> true

## The raised error reports the configured cap and a positive retry_after,
## which the shared RetryAfterHeader middleware turns into the HTTP header
begin
  @tester.enforce_create_account_rate_limit!(@ip_a)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?]
end
#=> [3, true]

## A different IP is unaffected by that lockout
@raises.call(@ip_b)
#=> false

## -- Missing IP skips rather than sharing a global bucket -----------------

## A nil IP does not build a blank "ip:" key. Sharing one bucket across every
## IP-less caller would let the first few lock it and deny everyone after —
## a global signup outage driven by whatever made the IP unresolvable.
result_nil = @raises.call(nil)
[result_nil, @redis.exists?('create_account:attempts:ip:')]
#=> [false, false]

## An empty-string IP behaves identically
result_empty = @raises.call('')
[result_empty, @redis.exists?('create_account:attempts:ip:')]
#=> [false, false]

## -- Audit trail ----------------------------------------------------------

## A cap-hit writes ONE queryable AdminAuditEvent, so a signup flood leaves
## more than a log line. Counted as a delta rather than by clearing the shared
## store, which other tryout files also write to.
set_create_account_rate_limit(
  'enabled' => true, 'max_per_ip' => 2, 'window' => 900, 'lockout' => 900,
)
@audit_verb  = Onetime::Security::CreateAccountRateLimiter::AUDIT_VERB
@audit_count = -> { Onetime::AdminAuditEvent.recent_security(500).count { |e| e['verb'] == @audit_verb } }
@admin_count = -> { Onetime::AdminAuditEvent.count }
@audit_ip    = '203.0.113.99'
cleanup(@redis, @audit_ip)
@audit_before = @audit_count.call
@admin_before = @admin_count.call
2.times { @raises.call(@audit_ip) }
@audit_count.call - @audit_before
#=> 1

## The event lands in the SECURITY trail, never the operator trail. That trail
## is count-capped with no TTL and evicts oldest-first, so this — the SECOND
## unauthenticated writer — sharing it could flush purge/role-change records.
@admin_count.call - @admin_before
#=> 0

## The event names the tier, the caps, and an unauthenticated actor
@audit_event = Onetime::AdminAuditEvent.recent_security(500).find { |e| e['verb'] == @audit_verb }
[@audit_event['actor'], @audit_event['result'], @audit_event['detail']['tier'],
 @audit_event['detail']['count'], @audit_event['detail']['max_attempts']]
#=> ['anonymous', 'failure', 'ip', 2, 2]

## The target is the OBSCURED IP (/16), never the resolved one
@audit_event['target']
#=> 'ip:203.0.x.x'

## Denied requests write NO further events: only the cap-reaching request
## records, bounding writes to one per masked network per lockout window. The
## AdminAuditEvent MAX_EVENTS rationale REQUIRES this of any unauthenticated
## writer; keep it.
3.times { @raises.call(@audit_ip) }
@audit_count.call - @audit_before
#=> 1

## ...and the flood still leaves the operator trail untouched
@admin_count.call - @admin_before
#=> 0

## -- Config validation ----------------------------------------------------

## Non-positive / garbage numeric settings fall back to the defaults instead of
## inverting enforcement (a zero cap would otherwise lock on the very first
## signup, and a non-positive lockout would make the Lua SETEX fail, turning
## every signup into a 500 rather than a throttle)
set_create_account_rate_limit(
  'enabled' => true, 'max_per_ip' => 0, 'window' => -5, 'lockout' => 'abc',
)
@cfg_ip = '198.51.100.77'
cleanup(@redis, @cfg_ip)
result_cfg = @raises.call(@cfg_ip)
[result_cfg, @redis.exists?("create_account:locked:ip:#{@cfg_ip}")]
#=> [false, false]

## -- Configured off -------------------------------------------------------

## With enabled:false the limiter is a total no-op even past the caps
set_create_account_rate_limit('enabled' => false, 'max_per_ip' => 3)
@off_ip = '192.0.2.55'
cleanup(@redis, @off_ip)
results = (1..6).map { @raises.call(@off_ip) }
results.none?
#=> true

## A disabled limiter writes no keys at all
@redis.exists?("create_account:attempts:ip:#{@off_ip}")
#=> false

## -- Collapsed IP operator hint (log line only) ---------------------------

## Without a declared trusted proxy the resolved client IP is REMOTE_ADDR, so a
## lockout may be deployment-wide — which for THIS limiter means signup is shut
## off for every new visitor. The hint says so and names the remedy inline. It
## is appended to a server LOG line, never to a response.
set_trusted_proxy_enabled(false)
hint = @tester.send(:collapsed_create_account_ip_hint)
[hint.empty?, hint.include?('trusted_proxy'), hint.include?('TRUSTED_PROXY_ENABLED=true')]
#=> [false, true, true]

## An absent trusted_proxy config reads the same as disabled
set_trusted_proxy_enabled(nil)
@tester.send(:collapsed_create_account_ip_hint).match?(/trusted_proxy/)
#=> true

## With the trusted proxy declared the hint is empty, so a correctly configured
## deployment's lockout line stays byte-identical
set_trusted_proxy_enabled(true)
@tester.send(:collapsed_create_account_ip_hint)
#=> ""

## The hint is WIRED IN: a REAL cap hit (trusted proxy not declared) emits
## exactly one OT.le line carrying both the cap text and the hint. The three
## cases above call the private helper directly, so they stay green even if the
## interpolation is dropped from enforce_create_account_rate_limit!; this case
## is the one that fails.
set_trusted_proxy_enabled(false)
set_create_account_rate_limit(
  'enabled' => true, 'max_per_ip' => 2, 'window' => 900, 'lockout' => 900,
)
@hint_ip = '192.0.2.99'
cleanup(@redis, @hint_ip)
captured = []
OT.singleton_class.alias_method(:__ca_hint_real_le, :le)
OT.define_singleton_method(:le) { |*msgs, **_payload| captured << msgs.join(' ') }
begin
  2.times { @tester.enforce_create_account_rate_limit!(@hint_ip) }
ensure
  OT.singleton_class.remove_method(:le)
  OT.singleton_class.alias_method(:le, :__ca_hint_real_le)
  OT.singleton_class.remove_method(:__ca_hint_real_le)
end
line = captured.find { |msg| msg.include?('hit cap') }.to_s
[
  captured.length,
  line.include?('[CreateAccountRateLimiter] ip'),
  line.include?('hit cap (2/2)'),
  line.include?('TRUSTED_PROXY_ENABLED=true'),
]
#=> [1, true, true, true]

## With the trusted proxy declared the same cap hit logs WITHOUT the hint
set_trusted_proxy_enabled(true)
@hint_ip_ok = '192.0.2.100'
cleanup(@redis, @hint_ip_ok)
captured_ok = []
OT.singleton_class.alias_method(:__ca_hint_real_le, :le)
OT.define_singleton_method(:le) { |*msgs, **_payload| captured_ok << msgs.join(' ') }
begin
  2.times { @tester.enforce_create_account_rate_limit!(@hint_ip_ok) }
ensure
  OT.singleton_class.remove_method(:le)
  OT.singleton_class.alias_method(:le, :__ca_hint_real_le)
  OT.singleton_class.remove_method(:__ca_hint_real_le)
end
line_ok = captured_ok.find { |msg| msg.include?('hit cap') }.to_s
[line_ok.end_with?('locked for 900s'), line_ok.include?('TRUSTED_PROXY_ENABLED')]
#=> [true, false]

# Clean up test keys and restore the shared config for later tryout files.
cleanup(@redis, @ip_a)
cleanup(@redis, @ip_b)
cleanup(@redis, @audit_ip)
cleanup(@redis, @cfg_ip)
cleanup(@redis, @off_ip)
cleanup(@redis, @hint_ip)
cleanup(@redis, @hint_ip_ok)
OT.send(:conf=, @saved_conf)
