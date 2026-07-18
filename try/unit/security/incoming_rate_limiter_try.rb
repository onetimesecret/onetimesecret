# try/unit/security/incoming_rate_limiter_try.rb
#
# frozen_string_literal: true

# AZ9: IncomingRateLimiter throttles anonymous incoming-secret submissions.
# Two tiers, mirroring the login/passphrase limiters:
#   1. Per-IP tier   - the tight gate (max_per_ip per window).
#   2. Per-recipient - a higher backstop keyed on the client-supplied hash.
#
# We test:
# 1. Under-limit submissions are allowed
# 2. Key shape and TTL of the per-IP attempts counter
# 3. Over-limit raises LimitExceeded with the configured cap + lockout state
# 4. nil-IP falls back to the per-recipient tier only
# 5. The per-recipient backstop caps IP-less / IP-rotating callers
# 6. Configured-off (enabled:false) is a total no-op

require_relative '../../support/test_models'
require 'onetime/security/incoming_rate_limiter'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

# Enable the limiter with small, known caps (test config ships it disabled).
def set_incoming_rate_limit(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['features'] ||= {}
  new_conf['features']['incoming'] ||= {}
  new_conf['features']['incoming']['rate_limit'] = cfg
  OT.send(:conf=, new_conf)
end

set_incoming_rate_limit(
  'enabled' => true,
  'max_per_ip' => 3,
  'max_per_recipient' => 5,
  'window' => 900,
  'lockout' => 900,
)

class IncomingRateLimiterTester
  include Onetime::Security::IncomingRateLimiter
end

@tester = IncomingRateLimiterTester.new
@redis  = Familia.dbclient

@ip_a   = '203.0.113.10'
@ip_b   = '198.51.100.20'
@rcpt_a = "rcpt_a_#{Familia.now.to_i}_#{rand(10_000)}"
@rcpt_b = "rcpt_b_#{Familia.now.to_i}_#{rand(10_000)}"
@rcpt_c = "rcpt_c_#{Familia.now.to_i}_#{rand(10_000)}"

# true if a single enforce call raises LimitExceeded, false otherwise.
@raises = lambda do |ip, rcpt = nil|
  @tester.enforce_incoming_rate_limit!(ip, rcpt)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, ip: nil, rcpt: nil)
  keys = []
  keys += ["incoming:attempts:ip:#{ip}", "incoming:locked:ip:#{ip}"] if ip
  keys += ["incoming:attempts:rcpt:#{rcpt}", "incoming:locked:rcpt:#{rcpt}"] if rcpt
  redis.del(*keys) unless keys.empty?
end

cleanup(@redis, ip: @ip_a, rcpt: @rcpt_a)
cleanup(@redis, ip: @ip_b, rcpt: @rcpt_b)
cleanup(@redis, rcpt: @rcpt_c)

## -- Under-limit ----------------------------------------------------------

## A single submission under the cap is allowed
@raises.call(@ip_a, @rcpt_a)
#=> false

## The per-IP attempts counter uses the documented key shape
@redis.exists?("incoming:attempts:ip:#{@ip_a}")
#=> true

## The per-IP counter carries a TTL within the configured window
ttl = @redis.ttl("incoming:attempts:ip:#{@ip_a}")
ttl.positive? && ttl <= 900
#=> true

## The per-recipient counter is also written on the same submission
@redis.exists?("incoming:attempts:rcpt:#{@rcpt_a}")
#=> true

## -- Over-limit (per-IP tier trips first at max_per_ip=3) -----------------

## Two more submissions reach the per-IP cap (total 3) and lock the IP tier
[@raises.call(@ip_a, @rcpt_a), @raises.call(@ip_a, @rcpt_a)]
#=> [false, false]

## The per-IP lockout key is now set
@redis.exists?("incoming:locked:ip:#{@ip_a}")
#=> true

## The per-IP attempts counter is cleared once the tier locks
@redis.exists?("incoming:attempts:ip:#{@ip_a}")
#=> false

## The next submission from that IP raises LimitExceeded
@raises.call(@ip_a, @rcpt_a)
#=> true

## The raised error reports the per-IP cap and a positive retry_after
begin
  @tester.enforce_incoming_rate_limit!(@ip_a, @rcpt_a)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?]
end
#=> [3, true]

## A different IP for the same recipient is still allowed (recipient tier < cap)
@raises.call(@ip_b, @rcpt_a)
#=> false

## -- nil-IP falls back to the per-recipient tier only ---------------------

## A nil-IP submission does not build a blank "ip:" key
@raises.call(nil, @rcpt_c)
[@redis.exists?("incoming:attempts:ip:"), @redis.exists?("incoming:attempts:rcpt:#{@rcpt_c}")]
#=> [false, true]

## With neither IP nor recipient the limiter is a complete no-op: no raise,
## and neither tier writes a blank-suffixed key
result = @raises.call(nil, nil)
[result, @redis.exists?("incoming:attempts:ip:"), @redis.exists?("incoming:attempts:rcpt:")]
#=> [false, false, false]

## -- Per-recipient backstop (max_per_recipient=5) -------------------------

## Five nil-IP submissions reach the recipient cap and lock the recipient tier
cleanup(@redis, rcpt: @rcpt_b)
5.times { @tester.enforce_incoming_rate_limit!(nil, @rcpt_b) }
@redis.exists?("incoming:locked:rcpt:#{@rcpt_b}")
#=> true

## The next submission for that recipient raises, reporting the recipient cap
begin
  @tester.enforce_incoming_rate_limit!(nil, @rcpt_b)
  nil
rescue Onetime::LimitExceeded => e
  e.max_attempts
end
#=> 5

## -- Configured off -------------------------------------------------------

## With enabled:false the limiter is a total no-op even past the caps
set_incoming_rate_limit('enabled' => false, 'max_per_ip' => 3, 'max_per_recipient' => 5)
@off_ip   = '192.0.2.55'
@off_rcpt = "rcpt_off_#{Familia.now.to_i}_#{rand(10_000)}"
cleanup(@redis, ip: @off_ip, rcpt: @off_rcpt)
results = (1..6).map { @raises.call(@off_ip, @off_rcpt) }
results.none?
#=> true

## Disabled limiter writes no keys at all
[@redis.exists?("incoming:attempts:ip:#{@off_ip}"), @redis.exists?("incoming:attempts:rcpt:#{@off_rcpt}")]
#=> [false, false]

# Clean up test keys and restore the shared config for later tryout files.
cleanup(@redis, ip: @ip_a, rcpt: @rcpt_a)
cleanup(@redis, ip: @ip_b, rcpt: @rcpt_b)
cleanup(@redis, rcpt: @rcpt_c)
cleanup(@redis, ip: @off_ip, rcpt: @off_rcpt)
OT.send(:conf=, @saved_conf)
