# try/unit/security/reset_request_rate_limiter_try.rb
#
# frozen_string_literal: true

# #3872: ResetRequestRateLimiter throttles reset-password-request submissions,
# bounding the sampling throughput of the timing residual accepted by the
# enumeration-safe route (#3857). Two tiers, mirroring IncomingRateLimiter:
#   1. Per-IP tier    - the tight gate (max_per_ip per window).
#   2. Per-email tier - a higher backstop keyed on the NORMALIZED submitted
#                       login (catches IP-rotating callers).
#
# We test:
# 1. Under-limit requests are allowed
# 2. Key shape and TTL of the per-IP attempts counter
# 3. Over-limit raises LimitExceeded with the configured cap + lockout state
# 4. Login normalization (Rodauth-parity: case/whitespace variants, Unicode
#    case-folding, and control characters all land in one bucket)
# 5. nil-IP falls back to the per-email tier only
# 6. The per-email backstop caps IP-rotating callers
# 7. Configured-off (enabled:false) is a total no-op

require_relative '../../support/test_models'
require 'onetime/security/reset_request_rate_limiter'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

# Enable the limiter with small, known caps (test config ships it disabled).
def set_reset_request_rate_limit(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['authentication'] ||= {}
  new_conf['site']['authentication']['reset_request_rate_limit'] = cfg
  OT.send(:conf=, new_conf)
end

set_reset_request_rate_limit(
  'enabled' => true,
  'max_per_ip' => 3,
  'max_per_email' => 5,
  'window' => 900,
  'lockout' => 900,
)

class ResetRequestRateLimiterTester
  include Onetime::Security::ResetRequestRateLimiter
end

@tester = ResetRequestRateLimiterTester.new
@redis  = Onetime::Customer.dbclient

@ip_a    = '203.0.113.10'
@ip_b    = '198.51.100.20'
@tag     = "#{Familia.now.to_i}_#{rand(10_000)}"
@email_a = "target_a_#{@tag}@example.com"
@email_b = "target_b_#{@tag}@example.com"
@email_c = "target_c_#{@tag}@example.com"
# The bucket an eszett-variant login must case-fold into (U+00DF folds to
# "ss").
@email_fold = "fold_ss_#{@tag}@example.com"

# true if a single enforce call raises LimitExceeded, false otherwise.
@raises = lambda do |ip, login = nil|
  @tester.enforce_reset_request_rate_limit!(ip, login)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, ip: nil, email: nil)
  keys = []
  keys += ["reset_request:attempts:ip:#{ip}", "reset_request:locked:ip:#{ip}"] if ip
  keys += ["reset_request:attempts:email:#{email}", "reset_request:locked:email:#{email}"] if email
  redis.del(*keys) unless keys.empty?
end

cleanup(@redis, ip: @ip_a, email: @email_a)
cleanup(@redis, ip: @ip_b, email: @email_b)
cleanup(@redis, email: @email_c)
cleanup(@redis, email: @email_fold)

## -- Under-limit ----------------------------------------------------------

## A single request under the cap is allowed
@raises.call(@ip_a, @email_a)
#=> false

## The per-IP attempts counter uses the documented key shape
@redis.exists?("reset_request:attempts:ip:#{@ip_a}")
#=> true

## The per-IP counter carries a TTL within the configured window
ttl = @redis.ttl("reset_request:attempts:ip:#{@ip_a}")
ttl.positive? && ttl <= 900
#=> true

## The per-email counter is also written on the same request
@redis.exists?("reset_request:attempts:email:#{@email_a}")
#=> true

## -- Login normalization --------------------------------------------------

## Case/whitespace variants of one target land in the SAME per-email bucket
@tester.enforce_reset_request_rate_limit!(@ip_b, "  #{@email_a.upcase}  ")
@redis.get("reset_request:attempts:email:#{@email_a}").to_i
#=> 2

## Unicode case-folding and control characters cannot dodge the bucket either:
## normalization mirrors Rodauth's normalize_login (OT::Utils.normalize_email,
## NFC + case-fold), so an eszett (U+00DF) variant with an embedded control
## character folds into the plain-ss bucket Rodauth would resolve the account
## from
@tester.enforce_reset_request_rate_limit!(nil, "\u0000fold_\u00df_#{@tag}@EXAMPLE.com\r\n")
@redis.get("reset_request:attempts:email:#{@email_fold}").to_i
#=> 1

## -- Over-limit (per-IP tier trips first at max_per_ip=3) -----------------

## Two more requests reach the per-IP cap (total 3) and lock the IP tier
[@raises.call(@ip_a, @email_a), @raises.call(@ip_a, @email_a)]
#=> [false, false]

## The per-IP lockout key is now set
@redis.exists?("reset_request:locked:ip:#{@ip_a}")
#=> true

## The per-IP attempts counter is cleared once the tier locks
@redis.exists?("reset_request:attempts:ip:#{@ip_a}")
#=> false

## The next request from that IP raises LimitExceeded
@raises.call(@ip_a, @email_a)
#=> true

## The raised error reports the per-IP cap and a positive retry_after
begin
  @tester.enforce_reset_request_rate_limit!(@ip_a, @email_a)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?]
end
#=> [3, true]

## -- nil-IP falls back to the per-email tier only -------------------------

## A nil-IP request does not build a blank "ip:" key
@raises.call(nil, @email_c)
[@redis.exists?("reset_request:attempts:ip:"), @redis.exists?("reset_request:attempts:email:#{@email_c}")]
#=> [false, true]

## With neither IP nor login the limiter is a complete no-op: no raise,
## and neither tier writes a blank-suffixed key
result = @raises.call(nil, nil)
[result, @redis.exists?("reset_request:attempts:ip:"), @redis.exists?("reset_request:attempts:email:")]
#=> [false, false, false]

## -- Per-email backstop (max_per_email=5) ---------------------------------

## Five nil-IP requests reach the per-email cap and lock the email tier
cleanup(@redis, email: @email_b)
5.times { @tester.enforce_reset_request_rate_limit!(nil, @email_b) }
@redis.exists?("reset_request:locked:email:#{@email_b}")
#=> true

## The next request for that login raises, reporting the per-email cap
begin
  @tester.enforce_reset_request_rate_limit!(nil, @email_b)
  nil
rescue Onetime::LimitExceeded => e
  e.max_attempts
end
#=> 5

## An IP-rotating caller (fresh IP each time) is still capped by the email tier
@raises.call(@ip_b, @email_b)
#=> true

## -- Configured off -------------------------------------------------------

## With enabled:false the limiter is a total no-op even past the caps
set_reset_request_rate_limit('enabled' => false, 'max_per_ip' => 3, 'max_per_email' => 5)
@off_ip    = '192.0.2.55'
@off_email = "target_off_#{Familia.now.to_i}_#{rand(10_000)}@example.com"
cleanup(@redis, ip: @off_ip, email: @off_email)
results = (1..6).map { @raises.call(@off_ip, @off_email) }
results.none?
#=> true

## Disabled limiter writes no keys at all
[@redis.exists?("reset_request:attempts:ip:#{@off_ip}"), @redis.exists?("reset_request:attempts:email:#{@off_email}")]
#=> [false, false]

# Clean up test keys and restore the shared config for later tryout files.
cleanup(@redis, ip: @ip_a, email: @email_a)
cleanup(@redis, ip: @ip_b, email: @email_b)
cleanup(@redis, email: @email_c)
cleanup(@redis, email: @email_fold)
cleanup(@redis, ip: @off_ip, email: @off_email)
OT.send(:conf=, @saved_conf)
