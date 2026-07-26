# try/unit/security/passphrase_rate_limiter_try.rb
#
# frozen_string_literal: true

# These tryouts test the PassphraseRateLimiter module functionality.
# The PassphraseRateLimiter prevents brute-force attacks on secret passphrases
# with a TWO-TIER design (M-8):
#
#   1. Per-secret+IP tier  - locks a single client at MAX_ATTEMPTS (the tight
#      gate). Threading client_ip means an attacker cannot lock out the
#      legitimate recipient by burning wrong guesses on one secret link.
#   2. Per-secret global backstop - locks at GLOBAL_MAX_ATTEMPTS. Catches an
#      IP-rotating attacker and nil-IP callers (who share this bucket by secret).
#
# We're testing:
# 1. Per-IP tier isolation (attacker IP locked while victim IP still allowed)
# 2. nil-IP callers falling back to the global cap (GLOBAL_MAX_ATTEMPTS, not 5)
# 3. The global backstop catching an IP-rotating attacker
# 4. Clearing both tiers on success
# 5. Empty / nil identifier guards

require_relative '../../support/test_models'
require 'onetime/security/passphrase_rate_limiter'

OT.boot! :test, true

# The admin Inspect/Reset ops share the passphrase key templates via the
# registry; requiring them here lets the RL-1 section prove an operator can
# reach the per-IP lockouts the tight tier writes.
require 'onetime/operations/ratelimit/inspect'
require 'onetime/operations/ratelimit/reset'

# Include the module in a test class
class PassphraseRateLimiterTester
  include Onetime::Security::PassphraseRateLimiter
end

@tester = PassphraseRateLimiterTester.new
@redis  = Onetime::Secret.dbclient

MAX_ATTEMPTS        = Onetime::Security::PassphraseRateLimiter::MAX_ATTEMPTS
GLOBAL_MAX_ATTEMPTS = Onetime::Security::PassphraseRateLimiter::GLOBAL_MAX_ATTEMPTS

@attacker_ip = '203.0.113.7'
@victim_ip   = '198.51.100.9'

@sid_a = "test_secret_a_#{Familia.now.to_i}_#{rand(10_000)}"
@sid_b = "test_secret_b_#{Familia.now.to_i}_#{rand(10_000)}"
@sid_c = "test_secret_c_#{Familia.now.to_i}_#{rand(10_000)}"

# Returns true if check raises LimitExceeded, false otherwise.
@raises_limit = lambda do |sid, ip = nil|
  @tester.check_passphrase_rate_limit!(sid, ip)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup_keys(redis, sid, *ips)
  keys = ["passphrase:attempts:#{sid}", "passphrase:locked:#{sid}"]
  ips.each do |ip|
    keys << "passphrase:attempts:#{sid}:#{ip}"
    keys << "passphrase:locked:#{sid}:#{ip}"
  end
  redis.del(*keys)
end

cleanup_keys(@redis, @sid_a, @attacker_ip, @victim_ip)

## -- Tier 1: per-secret+IP isolation --------------------------------------

## Recording MAX_ATTEMPTS failures from the attacker IP returns the per-IP count
counts = (1..MAX_ATTEMPTS).map { @tester.record_failed_passphrase_attempt!(@sid_a, @attacker_ip) }
counts
#=> [1, 2, 3, 4, 5]

## The per-IP lockout key exists for the attacker IP
@redis.exists?("passphrase:locked:#{@sid_a}:#{@attacker_ip}")
#=> true

## The per-IP attempts counter is cleared once the tier locks
@redis.exists?("passphrase:attempts:#{@sid_a}:#{@attacker_ip}")
#=> false

## The attacker IP is now rate limited
@raises_limit.call(@sid_a, @attacker_ip)
#=> true

## A different (victim) IP for the SAME secret is NOT rate limited
@raises_limit.call(@sid_a, @victim_ip)
#=> false

## A nil-IP caller for the same secret is NOT rate limited (global still < cap)
@raises_limit.call(@sid_a)
#=> false

## The global backstop lockout has NOT tripped from 5 same-IP attempts
@redis.exists?("passphrase:locked:#{@sid_a}")
#=> false

## The per-IP lock reports MAX_ATTEMPTS as max_attempts
begin
  @tester.check_passphrase_rate_limit!(@sid_a, @attacker_ip)
  nil
rescue Onetime::LimitExceeded => e
  [e.retry_after.positive?, e.max_attempts]
end
#=> [true, MAX_ATTEMPTS]

## clear_passphrase_rate_limit! clears BOTH tiers for that IP
@tester.clear_passphrase_rate_limit!(@sid_a, @attacker_ip)
[@redis.exists?("passphrase:locked:#{@sid_a}:#{@attacker_ip}"), @redis.exists?("passphrase:locked:#{@sid_a}")]
#=> [false, false]

## After clearing, the previously-locked attacker IP is allowed again
@raises_limit.call(@sid_a, @attacker_ip)
#=> false

## -- Tier 2: nil-IP falls back to the global cap, not the tight 5 ----------

## Five nil-IP failures do NOT lock (nil-IP uses GLOBAL_MAX_ATTEMPTS, not 5)
cleanup_keys(@redis, @sid_c)
MAX_ATTEMPTS.times { @tester.record_failed_passphrase_attempt!(@sid_c) }
@raises_limit.call(@sid_c)
#=> false

## Reaching GLOBAL_MAX_ATTEMPTS nil-IP failures DOES lock via the backstop
(GLOBAL_MAX_ATTEMPTS - MAX_ATTEMPTS).times { @tester.record_failed_passphrase_attempt!(@sid_c) }
@raises_limit.call(@sid_c)
#=> true

## The global lock reports GLOBAL_MAX_ATTEMPTS as max_attempts
begin
  @tester.check_passphrase_rate_limit!(@sid_c)
  nil
rescue Onetime::LimitExceeded => e
  e.max_attempts
end
#=> GLOBAL_MAX_ATTEMPTS

## -- Tier 2: the global backstop catches an IP-rotating attacker -----------

## GLOBAL_MAX_ATTEMPTS failures across distinct IPs trip the global lock
GLOBAL_MAX_ATTEMPTS.times { |i| @tester.record_failed_passphrase_attempt!(@sid_b, "10.0.0.#{i}") }
@redis.exists?("passphrase:locked:#{@sid_b}")
#=> true

## A fresh, never-seen IP is now blocked by the global backstop
@raises_limit.call(@sid_b, '10.9.9.9')
#=> true

## A nil-IP caller is likewise blocked once the global backstop is locked
@raises_limit.call(@sid_b)
#=> true

## -- Guards ---------------------------------------------------------------

## Empty identifier should not cause errors
@tester.record_failed_passphrase_attempt!('')
#=> 0

## Empty identifier with an IP should not cause errors
@tester.record_failed_passphrase_attempt!('', @attacker_ip)
#=> 0

## Nil identifier should not cause errors
@tester.record_failed_passphrase_attempt!(nil)
#=> 0

## An empty-string IP falls back to the global tier (never builds a "...:" key)
@sid_d = "test_secret_d_#{Familia.now.to_i}_#{rand(10_000)}"
cleanup_keys(@redis, @sid_d)
@tester.record_failed_passphrase_attempt!(@sid_d, '')
[@redis.exists?("passphrase:attempts:#{@sid_d}"), @redis.exists?("passphrase:attempts:#{@sid_d}:")]
#=> [true, false]

## -- RL-1: the operator Reset/Inspect ops reach the per-IP lockout via SCAN -
# The tight per-IP tier writes `passphrase:locked:{sid}:{ip}`. The exact-key
# registry set can't name the {ip}, so before RL-1 `bin/ots ratelimit reset`
# and the colonel Inspect could neither SEE nor CLEAR a /24-collision lockout
# (the recipient stayed locked 30 min with no operator remedy). Both ops now
# SCAN the registry's per-IP patterns.

## Locking the tight per-IP tier writes a per-IP lockout the exact keys can't name
@sid_e = "test_secret_e_#{Familia.now.to_i}_#{rand(10_000)}"
cleanup_keys(@redis, @sid_e, @attacker_ip)
MAX_ATTEMPTS.times { @tester.record_failed_passphrase_attempt!(@sid_e, @attacker_ip) }
@redis.exists?("passphrase:locked:#{@sid_e}:#{@attacker_ip}")
#=> true

## Inspect (op) SCANs the per-IP tier and surfaces the lockout key
@insp = Onetime::Operations::RateLimit::Inspect.new(kind: 'passphrase', subject: @sid_e).call
@insp.entries.any? { |e| e.key == "passphrase:locked:#{@sid_e}:#{@attacker_ip}" && e.exists }
#=> true

## Reset (op) SCANs + deletes the per-IP lockout and reports :success
@reset = Onetime::Operations::RateLimit::Reset.new(kind: 'passphrase', subject: @sid_e, actor: 'ur1colonelpub').call
[@reset.status, @redis.exists?("passphrase:locked:#{@sid_e}:#{@attacker_ip}")]
#=> [:success, false]

## After the operator reset, the previously-locked attacker IP is allowed again
@raises_limit.call(@sid_e, @attacker_ip)
#=> false

# Clean up test keys
cleanup_keys(@redis, @sid_e, @attacker_ip)
cleanup_keys(@redis, @sid_a, @attacker_ip, @victim_ip)
cleanup_keys(@redis, @sid_c)
cleanup_keys(@redis, @sid_d)
GLOBAL_MAX_ATTEMPTS.times { |i| @redis.del("passphrase:attempts:#{@sid_b}:10.0.0.#{i}", "passphrase:locked:#{@sid_b}:10.0.0.#{i}") }
cleanup_keys(@redis, @sid_b, '10.9.9.9')
