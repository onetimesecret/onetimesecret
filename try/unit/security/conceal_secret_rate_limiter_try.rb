# try/unit/security/conceal_secret_rate_limiter_try.rb
#
# frozen_string_literal: true

# Finding F-02 (2026-08-14 audit): ConcealSecretRateLimiter caps ANONYMOUS
# secret creation, which previously had no limiter on the modern API surface —
# one Receipt + one Secret per request (each carrying anonymous-lifetime TTL). A
# single anonymous client sustained ~113 req/s at ~18 KiB/secret, writing ~1 GiB
# of Redis in ~8.6 minutes; since Redis also holds sessions that is a full
# outage.
#
# Single tier, keyed on the masked client IP alone. An anonymous conceal holds
# no account-derived identifier to key on, and keying on the secret body would
# mint one bucket per request (capping nothing).
#
# We test:
# 1. Under-limit requests are allowed; key shape and TTL
# 2. Over-limit raises LimitExceeded with the configured cap + lockout state
# 3. Normal creation still works from an unaffected IP
# 4. nil/empty IP skips rather than sharing one global bucket
# 5. Cap-hit writes exactly one ColonelAuditEvent, in the SECURITY trail, and
#    denied requests write no further ones
# 6. Garbage/non-positive config falls back to defaults instead of inverting
# 7. Configured-off (enabled:false) is a total no-op
# 8. The collapsed-IP operator hint is present and WIRED IN to the log line

require_relative '../../support/test_models'
require 'onetime/security/conceal_secret_rate_limiter'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

# Enable the limiter with small, known caps (test config ships it disabled).
def set_conceal_secret_rate_limit(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['secret_options'] ||= {}
  new_conf['site']['secret_options']['create_rate_limit'] = cfg
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

set_conceal_secret_rate_limit(
  'enabled' => true,
  'max_per_ip' => 3,
  'window' => 900,
  'lockout' => 900,
)

class ConcealSecretRateLimiterTester
  include Onetime::Security::ConcealSecretRateLimiter
end

@tester = ConcealSecretRateLimiterTester.new
@redis  = Onetime::Secret.dbclient

@ip_a = '203.0.113.10'
@ip_b = '198.51.100.20'

# true if a single enforce call raises LimitExceeded, false otherwise.
@raises = lambda do |ip|
  @tester.enforce_conceal_secret_rate_limit!(ip)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, ip)
  redis.del("create_secret:attempts:ip:#{ip}", "create_secret:locked:ip:#{ip}")
end

cleanup(@redis, @ip_a)
cleanup(@redis, @ip_b)

## -- Under-limit ----------------------------------------------------------

## A single creation under the cap is allowed
@raises.call(@ip_a)
#=> false

## The attempts counter uses the documented key shape (the one the ratelimit
## Registry and the bin/ots CLI emit commands for)
@redis.exists?("create_secret:attempts:ip:#{@ip_a}")
#=> true

## The counter carries a TTL within the configured window
ttl = @redis.ttl("create_secret:attempts:ip:#{@ip_a}")
ttl.positive? && ttl <= 900
#=> true

## -- Over-limit (cap = 3) -------------------------------------------------

## Two more requests reach the cap (total 3) and lock the tier
[@raises.call(@ip_a), @raises.call(@ip_a)]
#=> [false, false]

## The lockout key is now set
@redis.exists?("create_secret:locked:ip:#{@ip_a}")
#=> true

## The attempts counter is cleared once the tier locks
@redis.exists?("create_secret:attempts:ip:#{@ip_a}")
#=> false

## The next creation from that IP raises LimitExceeded
@raises.call(@ip_a)
#=> true

## The raised error reports the configured cap and a positive retry_after,
## which the shared RetryAfterHeader middleware turns into the HTTP header
begin
  @tester.enforce_conceal_secret_rate_limit!(@ip_a)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?]
end
#=> [3, true]

## Normal creation still works: a different IP is unaffected by that lockout
@raises.call(@ip_b)
#=> false

## -- Missing IP skips rather than sharing a global bucket -----------------

## A nil IP does not build a blank "ip:" key. Sharing one bucket across every
## IP-less caller would let the first few lock it and deny everyone after —
## a global creation outage driven by whatever made the IP unresolvable.
result_nil = @raises.call(nil)
[result_nil, @redis.exists?('create_secret:attempts:ip:')]
#=> [false, false]

## An empty-string IP behaves identically
result_empty = @raises.call('')
[result_empty, @redis.exists?('create_secret:attempts:ip:')]
#=> [false, false]

## -- Audit trail ----------------------------------------------------------

## A cap-hit writes ONE queryable ColonelAuditEvent, so a creation flood leaves
## more than a log line. Counted as a delta rather than by clearing the shared
## store, which other tryout files also write to.
set_conceal_secret_rate_limit(
  'enabled' => true, 'max_per_ip' => 2, 'window' => 900, 'lockout' => 900,
)
@audit_verb  = Onetime::Security::ConcealSecretRateLimiter::AUDIT_VERB
@audit_count = -> { Onetime::ColonelAuditEvent.recent_security(500).count { |e| e['verb'] == @audit_verb } }
@admin_count = -> { Onetime::ColonelAuditEvent.count }
@audit_ip    = '203.0.113.99'
cleanup(@redis, @audit_ip)
@audit_before = @audit_count.call
@admin_before = @admin_count.call
2.times { @raises.call(@audit_ip) }
@audit_count.call - @audit_before
#=> 1

## The event lands in the SECURITY trail, never the count-capped operator trail
@admin_count.call - @admin_before
#=> 0

## The event names the tier, the caps, and an unauthenticated actor
@audit_event = Onetime::ColonelAuditEvent.recent_security(500).find { |e| e['verb'] == @audit_verb }
[@audit_event['actor'], @audit_event['result'], @audit_event['detail']['tier'],
 @audit_event['detail']['count'], @audit_event['detail']['max_attempts']]
#=> ['anonymous', 'failure', 'ip', 2, 2]

## The target is the OBSCURED IP (/16), never the resolved one
@audit_event['target']
#=> 'ip:203.0.x.x'

## Denied requests write NO further events: only the cap-reaching request
## records, bounding writes to one per masked network per lockout window.
3.times { @raises.call(@audit_ip) }
@audit_count.call - @audit_before
#=> 1

## -- Config validation ----------------------------------------------------

## Non-positive / garbage numeric settings fall back to the defaults instead of
## inverting enforcement (a zero cap would otherwise lock on the very first
## creation, and a non-positive lockout would make the Lua SETEX fail)
set_conceal_secret_rate_limit(
  'enabled' => true, 'max_per_ip' => 0, 'window' => -5, 'lockout' => 'abc',
)
@cfg_ip = '198.51.100.77'
cleanup(@redis, @cfg_ip)
result_cfg = @raises.call(@cfg_ip)
[result_cfg, @redis.exists?("create_secret:locked:ip:#{@cfg_ip}")]
#=> [false, false]

## A PARTIAL config block — present, but with every numeric key absent — falls
## back to the defaults rather than raising (NilClass#to_i is 0, taking the same
## not-positive path as a garbage value)
set_conceal_secret_rate_limit('enabled' => true)
[@tester.send(:conceal_secret_max_per_ip),
 @tester.send(:conceal_secret_window),
 @tester.send(:conceal_secret_lockout)]
#=> [Onetime::Security::ConcealSecretRateLimiter::DEFAULT_MAX_PER_IP, Onetime::Security::ConcealSecretRateLimiter::DEFAULT_WINDOW, Onetime::Security::ConcealSecretRateLimiter::DEFAULT_LOCKOUT]

## and it still enforces on those defaults rather than erroring
@partial_ip = '203.0.113.42'
cleanup(@redis, @partial_ip)
@raises.call(@partial_ip)
#=> false

## -- Configured off -------------------------------------------------------

## With enabled:false the limiter is a total no-op even past the caps
set_conceal_secret_rate_limit('enabled' => false, 'max_per_ip' => 3)
@off_ip = '192.0.2.55'
cleanup(@redis, @off_ip)
results = (1..6).map { @raises.call(@off_ip) }
results.none?
#=> true

## A disabled limiter writes no keys at all
@redis.exists?("create_secret:attempts:ip:#{@off_ip}")
#=> false

## -- Collapsed IP operator hint (log line only) ---------------------------

## Without a declared trusted proxy the resolved client IP is REMOTE_ADDR, so a
## lockout may be deployment-wide. The hint says so and names the remedy inline.
set_trusted_proxy_enabled(false)
hint = @tester.send(:collapsed_conceal_secret_ip_hint)
[hint.empty?, hint.include?('trusted_proxy'), hint.include?('TRUSTED_PROXY_ENABLED=true')]
#=> [false, true, true]

## With the trusted proxy declared the hint is empty, so a correctly configured
## deployment's lockout line stays byte-identical
set_trusted_proxy_enabled(true)
@tester.send(:collapsed_conceal_secret_ip_hint)
#=> ""

## The hint is WIRED IN: a REAL cap hit (trusted proxy not declared) emits
## exactly one OT.le line carrying both the cap text and the hint.
set_trusted_proxy_enabled(false)
set_conceal_secret_rate_limit(
  'enabled' => true, 'max_per_ip' => 2, 'window' => 900, 'lockout' => 900,
)
@hint_ip = '192.0.2.99'
cleanup(@redis, @hint_ip)
captured = []
OT.singleton_class.alias_method(:__cs_hint_real_le, :le)
OT.define_singleton_method(:le) { |*msgs, **_payload| captured << msgs.join(' ') }
begin
  2.times { @tester.enforce_conceal_secret_rate_limit!(@hint_ip) }
ensure
  OT.singleton_class.remove_method(:le)
  OT.singleton_class.alias_method(:le, :__cs_hint_real_le)
  OT.singleton_class.remove_method(:__cs_hint_real_le)
end
line = captured.find { |msg| msg.include?('hit cap') }.to_s
[
  captured.length,
  line.include?('[ConcealSecretRateLimiter] ip'),
  line.include?('hit cap (2/2)'),
  line.include?('TRUSTED_PROXY_ENABLED=true'),
]
#=> [1, true, true, true]

# Clean up test keys and restore the shared config for later tryout files.
cleanup(@redis, @ip_a)
cleanup(@redis, @ip_b)
cleanup(@redis, @audit_ip)
cleanup(@redis, @cfg_ip)
cleanup(@redis, @partial_ip)
cleanup(@redis, @off_ip)
cleanup(@redis, @hint_ip)
OT.send(:conf=, @saved_conf)
