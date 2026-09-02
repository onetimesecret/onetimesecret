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
# #4329 adds three more buckets over the same body — colonel:mutation (every
# mutating verb, charged from the logic base constructor), colonel:destructive
# (TIER 1 only, charged last so a rejected attempt costs nothing) and
# colonel:handle_resolve (the two session reads that may fall back to a bounded
# 10 000-key SCAN). All four are asserted here.
#
# We test, for every bucket:
# 1. Under-limit attempts are allowed
# 2. The EXACT key shape (it must stay byte-identical with the registry row, or
#    `bin/ots ratelimit`, GET /ratelimit/inspect and POST /ratelimit/reset cannot
#    see the keys) and the counter's TTL
# 3. At the cap: lockout key set, counter cleared, next call raises with the
#    configured max_attempts and a positive retry_after
# 4. A different colonel is unaffected (the bucket is per-identity)
# 5. A blank subject writes NO blank-suffixed key and never raises
# 6. enabled:false — at the bucket AND at the parent flag — is a total no-op
# 7. The buckets are INDEPENDENT: locking one leaves the others spending
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

# -- #4329: the mutation / destructive / handle-resolve buckets --------------
#
# Same body, same guarantees, three more prefixes. The lifecycle helper below
# runs the full nine-assertion sequence against one bucket and reports what the
# datastore actually saw, so each bucket is asserted as one readable expectation
# instead of nine near-identical copies.

set_colonel_rate_limit(
  'enabled' => true,
  'elevation' => { 'enabled' => true, 'max_attempts' => 3, 'window' => 900, 'lockout' => 900 },
  'mutation' => { 'enabled' => true, 'max_attempts' => 3, 'window' => 300, 'lockout' => 300 },
  'destructive' => { 'enabled' => true, 'max_attempts' => 3, 'window' => 300, 'lockout' => 900 },
  'handle_resolve' => { 'enabled' => true, 'max_attempts' => 3, 'window' => 300, 'lockout' => 300 },
)

# Drive one bucket from empty to locked out and report every observable.
# `enforce` is the module's public entry point for that bucket; `window` is the
# configured counting window, so the TTL assertion is bucket-specific.
def bucket_lifecycle(redis, prefix, cap, window, enforce)
  subject = "ur_#{prefix.tr(':', '_')}_#{Familia.now.to_i}_#{rand(100_000)}"
  other   = "#{subject}_other"
  attempts_key = "#{prefix}:attempts:#{subject}"
  lockout_key  = "#{prefix}:locked:#{subject}"
  raises = lambda do |subj|
    enforce.call(subj)
    false
  rescue Onetime::LimitExceeded
    true
  end

  redis.del(attempts_key, lockout_key)

  # cap - 1 calls stay under the limit, then the cap-reaching call is itself
  # ALLOWED and sets the lockout for the next one.
  under      = (1...cap).map { raises.call(subject) }
  ttl        = redis.ttl(attempts_key)
  at_cap     = raises.call(subject)
  over       = raises.call(subject)
  reported   = begin
    enforce.call(subject)
    nil
  rescue Onetime::LimitExceeded => e
    [e.max_attempts, e.retry_after.positive?]
  end

  result = {
    under_limit_allowed: under.none?,
    counter_ttl_within_window: ttl.positive? && ttl <= window,
    cap_reaching_call_allowed: at_cap == false,
    locked_after_cap: redis.exists?(lockout_key),
    counter_cleared_after_cap: redis.exists?(attempts_key) == false,
    next_call_raises: over,
    reported_cap_and_retry_after: reported,
    other_subject_unaffected: raises.call(other) == false,
    blank_subject_skipped: [raises.call(nil), raises.call('')].none?,
    blank_suffixed_keys_absent: [redis.exists?("#{prefix}:attempts:"),
                                 redis.exists?("#{prefix}:locked:"),].none?,
  }

  redis.del(attempts_key, lockout_key, "#{prefix}:attempts:#{other}", "#{prefix}:locked:#{other}")
  result
end

@expected_lifecycle = {
  under_limit_allowed: true,
  counter_ttl_within_window: true,
  cap_reaching_call_allowed: true,
  locked_after_cap: true,
  counter_cleared_after_cap: true,
  next_call_raises: true,
  reported_cap_and_retry_after: [3, true],
  other_subject_unaffected: true,
  blank_subject_skipped: true,
  blank_suffixed_keys_absent: true,
}

## The broad mutation bucket runs the whole lifecycle correctly
bucket_lifecycle(@redis, 'colonel:mutation', 3, 300,
                 ->(s) { @tester.enforce_colonel_mutation_limit!(s) })
#=> @expected_lifecycle

## The tight destructive bucket runs the whole lifecycle correctly
bucket_lifecycle(@redis, 'colonel:destructive', 3, 300,
                 ->(s) { @tester.enforce_colonel_destructive_limit!(s) })
#=> @expected_lifecycle

## The handle-resolve bucket runs the whole lifecycle correctly
bucket_lifecycle(@redis, 'colonel:handle_resolve', 3, 300,
                 ->(s) { @tester.enforce_colonel_handle_resolve_limit!(s) })
#=> @expected_lifecycle

## Every bucket's keys are exactly the registry templates filled with the
## subject — `bin/ots ratelimit`, GET /ratelimit/inspect and POST
## /ratelimit/reset all derive their keys from those templates, so a drift here
## is a limiter no operator can inspect or clear
%w[colonel_mutation colonel_destructive colonel_handle_resolve].map do |kind|
  Onetime::Operations::RateLimit::Registry::LIMITERS[kind][:keys].map { |t| format(t, 'ur_x') }
end
#=> [["colonel:mutation:attempts:ur_x", "colonel:mutation:locked:ur_x"], ["colonel:destructive:attempts:ur_x", "colonel:destructive:locked:ur_x"], ["colonel:handle_resolve:attempts:ur_x", "colonel:handle_resolve:locked:ur_x"]]

## The buckets are INDEPENDENT: exhausting the destructive budget must leave the
## operator able to reach POST /ratelimit/reset (a mutation) to clear it, which
## is the documented lockout recovery
@iso = "ur_iso_#{Familia.now.to_i}_#{rand(10_000)}"
4.times do
  @tester.enforce_colonel_destructive_limit!(@iso)
rescue Onetime::LimitExceeded
  nil
end
[begin
  @tester.enforce_colonel_destructive_limit!(@iso)
  false
rescue Onetime::LimitExceeded
  true
end,
 begin
   @tester.enforce_colonel_mutation_limit!(@iso)
   false
 rescue Onetime::LimitExceeded
   true
 end,]
#=> [true, false]

## A per-bucket enabled:false is a no-op for THAT bucket only
set_colonel_rate_limit(
  'enabled' => true,
  'destructive' => { 'enabled' => false, 'max_attempts' => 2 },
  'mutation' => { 'enabled' => true, 'max_attempts' => 2 },
)
@mixed = "ur_mixed_#{Familia.now.to_i}_#{rand(10_000)}"
@destructive_off = (1..5).map do
  @tester.enforce_colonel_destructive_limit!(@mixed)
  false
rescue Onetime::LimitExceeded
  true
end
@mutation_on = (1..5).map do
  @tester.enforce_colonel_mutation_limit!(@mixed)
  false
rescue Onetime::LimitExceeded
  true
end
[@destructive_off.none?, @mutation_on.any?,
 @redis.exists?("colonel:destructive:attempts:#{@mixed}")]
#=> [true, true, false]

## The PARENT flag short-circuits all four buckets — this is what
## spec/config.test.yaml relies on
set_colonel_rate_limit(
  'enabled' => false,
  'mutation' => { 'enabled' => true, 'max_attempts' => 2 },
  'destructive' => { 'enabled' => true, 'max_attempts' => 2 },
  'handle_resolve' => { 'enabled' => true, 'max_attempts' => 2 },
)
@parent_off = "ur_parent_off_#{Familia.now.to_i}_#{rand(10_000)}"
[[->(s) { @tester.enforce_colonel_mutation_limit!(s) },
  ->(s) { @tester.enforce_colonel_destructive_limit!(s) },
  ->(s) { @tester.enforce_colonel_handle_resolve_limit!(s) },].map do |enforce|
   (1..5).map do
     enforce.call(@parent_off)
     false
   rescue Onetime::LimitExceeded
     true
   end.none?
 end,
 @redis.keys("colonel:*:*:#{@parent_off}").empty?,]
#=> [[true, true, true], true]

# Clean up test keys and restore the shared config for later tryout files.
cleanup(@redis, @extid_a)
cleanup(@redis, @extid_b)
cleanup(@redis, @off_a)
cleanup(@redis, @off_b)
%w[colonel:mutation colonel:destructive colonel:handle_resolve].each do |prefix|
  [@iso, @mixed, @parent_off].each do |subject|
    @redis.del("#{prefix}:attempts:#{subject}", "#{prefix}:locked:#{subject}")
  end
end
OT.send(:conf=, @saved_conf)
