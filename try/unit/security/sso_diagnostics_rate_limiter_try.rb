# try/unit/security/sso_diagnostics_rate_limiter_try.rb
#
# frozen_string_literal: true

# SsoDiagnosticsRateLimiter caps "Check saved configuration" runs
# (POST /api/domains/:extid/sso/diagnostics) per acting customer. Every run
# contacts the identity provider, and for Entra ID sends the stored client
# secret in a client-credentials token request, so the volume is bounded.
#
# Keyed on the customer's PUBLIC extid: one actor, one budget, whichever
# domain they point it at.
#
# We test:
# 1. Under-limit runs are allowed; key shape and TTL
# 2. Over-limit raises LimitExceeded with the configured cap + lockout state
# 3. Different customers have independent buckets
# 4. A blank subject is refused (ArgumentError), never a shared blank bucket
# 5. Cap-hit writes exactly one ColonelAuditEvent, in the SECURITY trail, and
#    denied runs write no further ones
# 6. Garbage/non-positive config falls back to defaults instead of inverting
# 7. Configured-off (enabled:false) is a total no-op
# 8. The registry row derives the same keys the module writes

require_relative '../../support/test_models'
require 'onetime/security/sso_diagnostics_rate_limiter'
require 'onetime/operations/ratelimit/registry'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

# Enable the limiter with small, known caps (test config ships it disabled).
def set_sso_diagnostics_rate_limit(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['features'] ||= {}
  new_conf['features']['organizations'] ||= {}
  new_conf['features']['organizations']['sso_diagnostics_rate_limit'] = cfg
  OT.send(:conf=, new_conf)
end

set_sso_diagnostics_rate_limit(
  'enabled' => true,
  'max_per_customer' => 3,
  'window' => 900,
  'lockout' => 900,
)

class SsoDiagnosticsRateLimiterTester
  include Onetime::Security::SsoDiagnosticsRateLimiter
end

@tester = SsoDiagnosticsRateLimiterTester.new
@redis  = Onetime::Customer.dbclient

@tag        = "#{Familia.now.to_i}_#{rand(10_000)}"
@customer_a = "ur1ssodiag_a_#{@tag}"
@customer_b = "ur1ssodiag_b_#{@tag}"

# true if a single enforce call raises LimitExceeded, false otherwise.
@raises = lambda do |extid|
  @tester.enforce_sso_diagnostics_rate_limit!(extid)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, extid)
  redis.del("sso_diagnostics:attempts:#{extid}", "sso_diagnostics:locked:#{extid}")
end

cleanup(@redis, @customer_a)
cleanup(@redis, @customer_b)

## -- Under-limit ----------------------------------------------------------

## A single run under the cap is allowed
@raises.call(@customer_a)
#=> false

## The attempts counter uses the documented key shape (the one the ratelimit
## Registry and the bin/ots CLI emit commands for)
@redis.exists?("sso_diagnostics:attempts:#{@customer_a}")
#=> true

## The counter carries a TTL within the configured window
ttl = @redis.ttl("sso_diagnostics:attempts:#{@customer_a}")
ttl.positive? && ttl <= 900
#=> true

## -- Over-limit (cap = 3) -------------------------------------------------

## Two more runs reach the cap (total 3) and are themselves allowed
[@raises.call(@customer_a), @raises.call(@customer_a)]
#=> [false, false]

## The lockout key is now set
@redis.exists?("sso_diagnostics:locked:#{@customer_a}")
#=> true

## The attempts counter is cleared once the bucket locks
@redis.exists?("sso_diagnostics:attempts:#{@customer_a}")
#=> false

## The next run from that customer raises LimitExceeded
@raises.call(@customer_a)
#=> true

## The raised error reports the configured cap and a positive retry_after,
## which the shared RetryAfterHeader middleware turns into the HTTP header
begin
  @tester.enforce_sso_diagnostics_rate_limit!(@customer_a)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?, e.message]
end
#=> [3, true, 'Too many saved-configuration checks. Please try again later.']

## A different customer is unaffected by that lockout
@raises.call(@customer_b)
#=> false

## -- Blank subject is a programming error, not a shared bucket -------------

## The call site requires an authenticated customer first, so a blank extid
## can only mean the guard was skipped. Refuse loudly rather than build one
## "sso_diagnostics:attempts:" bucket that every such caller would share.
begin
  @tester.enforce_sso_diagnostics_rate_limit!('')
  :allowed
rescue ArgumentError
  :refused
end
#=> :refused

## nil is treated the same as blank
begin
  @tester.enforce_sso_diagnostics_rate_limit!(nil)
  :allowed
rescue ArgumentError
  :refused
end
#=> :refused

## ...and no blank-suffixed key was written either way
@redis.exists?('sso_diagnostics:attempts:')
#=> false

## -- Audit trail ----------------------------------------------------------

## A cap-hit writes ONE queryable ColonelAuditEvent. Counted as a delta rather
## than by clearing the shared store, which other tryout files also write to.
set_sso_diagnostics_rate_limit(
  'enabled' => true, 'max_per_customer' => 2, 'window' => 900, 'lockout' => 900,
)
@audit_verb     = Onetime::Security::SsoDiagnosticsRateLimiter::AUDIT_VERB
@audit_count    = -> { Onetime::ColonelAuditEvent.recent_security(500).count { |e| e['verb'] == @audit_verb } }
@admin_count    = -> { Onetime::ColonelAuditEvent.count }
@audit_customer = "ur1ssodiag_audit_#{@tag}"
cleanup(@redis, @audit_customer)
@audit_before = @audit_count.call
@admin_before = @admin_count.call
2.times { @raises.call(@audit_customer) }
@audit_count.call - @audit_before
#=> 1

## The event lands in the SECURITY trail, never the operator trail
@admin_count.call - @admin_before
#=> 0

## The event is actored by and targets the customer's public id, with the caps
@audit_event = Onetime::ColonelAuditEvent.recent_security(500).find do |e|
  e['verb'] == @audit_verb && e['actor'] == @audit_customer
end
[@audit_event['actor'], @audit_event['target'], @audit_event['result'],
 @audit_event['detail']['count'], @audit_event['detail']['max_attempts']]
#=> [@audit_customer, @audit_customer, 'failure', 2, 2]

## Denied runs write NO further events: only the cap-reaching run records,
## bounding writes to one per customer per lockout window
3.times { @raises.call(@audit_customer) }
@audit_count.call - @audit_before
#=> 1

## -- Config validation ----------------------------------------------------

## Non-positive / garbage numeric settings fall back to the defaults instead of
## inverting enforcement (a zero cap would otherwise lock on the very first
## run, and a non-positive lockout would make the Lua SETEX fail)
set_sso_diagnostics_rate_limit(
  'enabled' => true, 'max_per_customer' => 0, 'window' => -5, 'lockout' => 'abc',
)
@cfg_customer = "ur1ssodiag_cfg_#{@tag}"
cleanup(@redis, @cfg_customer)
result_cfg = @raises.call(@cfg_customer)
[result_cfg, @redis.exists?("sso_diagnostics:locked:#{@cfg_customer}")]
#=> [false, false]

## YAML booleans and floats (`max_per_customer: false`, an env override YAML
## parses as `true`, `12.5`) fall back to the defaults instead of raising:
## false.to_i is a NoMethodError, which would 500 every run
set_sso_diagnostics_rate_limit(
  'enabled' => true, 'max_per_customer' => false, 'window' => true, 'lockout' => 12.5,
)
[@tester.send(:sso_diagnostics_max_per_customer),
 @tester.send(:sso_diagnostics_window),
 @tester.send(:sso_diagnostics_lockout)]
#=> [Onetime::Security::SsoDiagnosticsRateLimiter::DEFAULT_MAX_PER_CUSTOMER, Onetime::Security::SsoDiagnosticsRateLimiter::DEFAULT_WINDOW, Onetime::Security::SsoDiagnosticsRateLimiter::DEFAULT_LOCKOUT]

## Numeric strings (an env-var override) still coerce, and in base 10
set_sso_diagnostics_rate_limit(
  'enabled' => true, 'max_per_customer' => '7', 'window' => ' 600 ', 'lockout' => '010',
)
[@tester.send(:sso_diagnostics_max_per_customer),
 @tester.send(:sso_diagnostics_window),
 @tester.send(:sso_diagnostics_lockout)]
#=> [7, 600, 10]

## A PARTIAL config block — present, but with every numeric key absent — falls
## back to the defaults rather than raising
set_sso_diagnostics_rate_limit('enabled' => true)
[@tester.send(:sso_diagnostics_max_per_customer),
 @tester.send(:sso_diagnostics_window),
 @tester.send(:sso_diagnostics_lockout)]
#=> [Onetime::Security::SsoDiagnosticsRateLimiter::DEFAULT_MAX_PER_CUSTOMER, Onetime::Security::SsoDiagnosticsRateLimiter::DEFAULT_WINDOW, Onetime::Security::SsoDiagnosticsRateLimiter::DEFAULT_LOCKOUT]

## An ABSENT config block is enabled with the defaults (protective default on)
new_conf = YAML.load(YAML.dump(OT.conf))
new_conf['features']['organizations'].delete('sso_diagnostics_rate_limit')
OT.send(:conf=, new_conf)
[@tester.send(:sso_diagnostics_rate_limit_enabled?), @tester.send(:sso_diagnostics_max_per_customer)]
#=> [true, Onetime::Security::SsoDiagnosticsRateLimiter::DEFAULT_MAX_PER_CUSTOMER]

## -- Configured off -------------------------------------------------------

## With enabled:false the limiter is a total no-op even past the caps
set_sso_diagnostics_rate_limit('enabled' => false, 'max_per_customer' => 3)
@off_customer = "ur1ssodiag_off_#{@tag}"
cleanup(@redis, @off_customer)
results = (1..6).map { @raises.call(@off_customer) }
results.none?
#=> true

## A disabled limiter writes no keys at all
@redis.exists?("sso_diagnostics:attempts:#{@off_customer}")
#=> false

## A disabled limiter does not even inspect the subject
@raises.call('')
#=> false

## -- Registry -------------------------------------------------------------

## The registry row derives exactly the keys the module writes, so the
## bin/ots CLI and the colonel inspect/reset endpoints can see them
Onetime::Operations::RateLimit::Registry.keys_for('sso_diagnostics', @customer_a)
#=> ["sso_diagnostics:attempts:#{@customer_a}", "sso_diagnostics:locked:#{@customer_a}"]

## ...on the Customer shard, matching the module's own accessor
Onetime::Operations::RateLimit::Registry.fetch('sso_diagnostics')[:dbclient].call.equal?(@tester.send(:sso_diagnostics_redis))
#=> true

# Teardown: restore the booted config for later tryout files and clear keys.
[@customer_a, @customer_b, @audit_customer, @cfg_customer, @off_customer].each { |extid| cleanup(@redis, extid) }
OT.send(:conf=, @saved_conf)
