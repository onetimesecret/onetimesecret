# try/unit/security/colonel_rate_limiter_try.rb
#
# frozen_string_literal: true

# #4327: ColonelRateLimiter throttles colonel step-up (sudo) attempts.
#
# The first limiter in the repo keyed on an AUTHENTICATED identity rather than a
# perimeter IP: the subject is `cust.extid`, the acting colonel's PUBLIC id and
# the same value every colonel op passes as its audit `actor`. Per-ACCOUNT, not
# per-session — a per-session bucket bounds one cookie, and an attacker with any
# second way in gets a fresh budget.
#
# It matters that this is enforced at all: the Rodauth password check behind
# POST /api/colonel/elevation is an INTERNAL REQUEST, so it is not a login and
# does not increment Rodauth's own lockout counter. This module is the only
# backstop against guessing there.
#
# We test:
# 1. Under-limit attempts are allowed
# 2. The EXACT key shape (it must stay byte-identical with the registry row, or
#    `bin/ots ratelimit`, GET /ratelimit/inspect and POST /ratelimit/reset cannot
#    see the keys) and the counter's TTL
# 3. At the cap: lockout key set, counter cleared, next call raises with the
#    configured max_attempts and a positive retry_after
# 4. A different colonel is unaffected (the bucket is per-identity)
# 5. A blank subject writes NO blank-suffixed key and never raises
# 6. enabled:false — at the bucket AND at the parent flag — is a total no-op
#
# Run: try --agent try/unit/security/colonel_rate_limiter_try.rb

require_relative '../../support/test_models'
require 'onetime/security/colonel_rate_limiter'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

# The test config ships site.admin.rate_limit disabled; enable it here with
# small, known caps.
def set_colonel_rate_limit(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['admin'] ||= {}
  new_conf['site']['admin']['rate_limit'] = cfg
  OT.send(:conf=, new_conf)
end

set_colonel_rate_limit(
  'enabled' => true,
  'elevation' => { 'enabled' => true, 'max_attempts' => 3, 'window' => 900, 'lockout' => 900 },
)

class ColonelRateLimiterTester
  include Onetime::Security::ColonelRateLimiter
end

@tester = ColonelRateLimiterTester.new
@redis  = Onetime::Customer.dbclient

@extid_a = "ur_a_#{Familia.now.to_i}_#{rand(10_000)}"
@extid_b = "ur_b_#{Familia.now.to_i}_#{rand(10_000)}"

# true if a single enforce call raises LimitExceeded, false otherwise.
@raises = lambda do |subject|
  @tester.enforce_colonel_elevation_limit!(subject)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, subject)
  redis.del("colonel:elevation:attempts:#{subject}", "colonel:elevation:locked:#{subject}")
end

cleanup(@redis, @extid_a)
cleanup(@redis, @extid_b)

## -- Under-limit ----------------------------------------------------------

## A single step-up attempt under the cap is allowed
@raises.call(@extid_a)
#=> false

## The attempts counter uses the key shape the registry row publishes
@redis.exists?("colonel:elevation:attempts:#{@extid_a}")
#=> true

## The counter carries a TTL inside the configured window
ttl = @redis.ttl("colonel:elevation:attempts:#{@extid_a}")
ttl.positive? && ttl <= 900
#=> true

## The key names are exactly the registry's templates filled with the subject
require 'onetime/operations/ratelimit/registry'
Onetime::Operations::RateLimit::Registry::LIMITERS['colonel_elevation'][:keys].map { |t| format(t, @extid_a) }
#=> ["colonel:elevation:attempts:#{@extid_a}", "colonel:elevation:locked:#{@extid_a}"]

## -- Over-limit (max_attempts = 3) ----------------------------------------

## Two more attempts reach the cap and lock the account
[@raises.call(@extid_a), @raises.call(@extid_a)]
#=> [false, false]

## The lockout key is now set
@redis.exists?("colonel:elevation:locked:#{@extid_a}")
#=> true

## The attempts counter is cleared once the bucket locks
@redis.exists?("colonel:elevation:attempts:#{@extid_a}")
#=> false

## The next attempt raises LimitExceeded
@raises.call(@extid_a)
#=> true

## The raised error reports the configured cap and a positive retry_after
begin
  @tester.enforce_colonel_elevation_limit!(@extid_a)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?]
end
#=> [3, true]

## A DIFFERENT colonel is unaffected: the bucket is per-identity, not global
@raises.call(@extid_b)
#=> false

## -- Blank subject --------------------------------------------------------

## A blank subject is skipped entirely rather than sharing one bucket — a
## blank-suffixed key would let the first few subject-less callers lock out
## every later one (a colonel-wide outage)
[@raises.call(nil), @raises.call(''),
 @redis.exists?('colonel:elevation:attempts:'), @redis.exists?('colonel:elevation:locked:')]
#=> [false, false, false, false]

## -- Configured off -------------------------------------------------------

## With the BUCKET disabled the limiter is a total no-op past the cap
set_colonel_rate_limit(
  'enabled' => true,
  'elevation' => { 'enabled' => false, 'max_attempts' => 3 },
)
@off_a = "ur_off_a_#{Familia.now.to_i}_#{rand(10_000)}"
cleanup(@redis, @off_a)
(1..6).map { @raises.call(@off_a) }.none?
#=> true

## ...and it writes no keys at all
[@redis.exists?("colonel:elevation:attempts:#{@off_a}"), @redis.exists?("colonel:elevation:locked:#{@off_a}")]
#=> [false, false]

## The PARENT flag short-circuits the bucket too — this is what
## spec/config.test.yaml relies on, so the colonel suites do not throttle
## themselves through one actor
set_colonel_rate_limit(
  'enabled' => false,
  'elevation' => { 'enabled' => true, 'max_attempts' => 3 },
)
@off_b = "ur_off_b_#{Familia.now.to_i}_#{rand(10_000)}"
cleanup(@redis, @off_b)
results = (1..6).map { @raises.call(@off_b) }
[results.none?, @redis.exists?("colonel:elevation:attempts:#{@off_b}")]
#=> [true, false]

# Clean up test keys and restore the shared config for later tryout files.
cleanup(@redis, @extid_a)
cleanup(@redis, @extid_b)
cleanup(@redis, @off_a)
cleanup(@redis, @off_b)
OT.send(:conf=, @saved_conf)
