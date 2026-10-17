# try/unit/security/email_login_request_rate_limiter_try.rb
#
# frozen_string_literal: true

# RISK-2026-08-14-M04: POST /auth/email-login-request is throttled by
# ResetRequestRateLimiter under its :email_login_request scope — the same two
# tiers (per masked IP, per normalized login) as the reset-request limiter,
# under their own keys, config block, audit verb and 429 message.
# reset_request_rate_limiter_try.rb covers the shared tier mechanics; this
# file covers what the scope changes and what it must leave alone.
#
# We test:
# 1. Keys use the email_login_request: prefix, for both tiers
# 2. The two scopes never share a bucket (no cross-charging either way)
# 3. The scope reads site.authentication.email_login_request_rate_limit
# 4. The 429 message, audit verb and log tag are the scope's own
# 5. Absent/garbage caps fall back to the scope's defaults (30 per IP)
# 6. enabled:false on one scope leaves the other enforcing
# 7. An unknown scope is a programming error (KeyError), even when disabled

require_relative '../../support/test_models'
require 'onetime/security/reset_request_rate_limiter'
require 'onetime/operations/ratelimit/registry'

OT.boot! :test, true

@saved_conf = YAML.load(YAML.dump(OT.conf))

# Replace one site.authentication block; the teardown restores @saved_conf.
def set_limit_block(key, cfg)
  new_conf       = YAML.load(YAML.dump(OT.conf))
  authentication = new_conf.dig('site', 'authentication')
  if cfg.nil?
    authentication.delete(key)
  else
    authentication[key] = cfg
  end
  OT.send(:conf=, new_conf)
end

set_limit_block(
  'email_login_request_rate_limit',
  'enabled' => true,
  'max_per_ip' => 3,
  'max_per_email' => 5,
  'window' => 900,
  'lockout' => 900,
)
set_limit_block(
  'reset_request_rate_limit',
  'enabled' => true,
  'max_per_ip' => 3,
  'max_per_email' => 5,
  'window' => 900,
  'lockout' => 900,
)

class EmailLoginRequestRateLimiterTester
  include Onetime::Security::ResetRequestRateLimiter
end

@tester = EmailLoginRequestRateLimiterTester.new
@redis  = Onetime::Customer.dbclient
@scopes = Onetime::Security::ResetRequestRateLimiter::SCOPES

@tag     = "#{Familia.now.to_i}_#{rand(10_000)}"
@ip      = '203.0.113.30'
@ip_b    = '198.51.100.31'
@email   = "magic_#{@tag}@example.com"
@email_b = "magic_b_#{@tag}@example.com"

@raises = ->(ip, login, scope = :email_login_request) do
  @tester.enforce_reset_request_rate_limit!(ip, login, scope: scope)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, ip: nil, email: nil)
  keys = []
  %w[email_login_request reset_request].each do |prefix|
    keys += ["#{prefix}:attempts:ip:#{ip}", "#{prefix}:locked:ip:#{ip}"] if ip
    keys += ["#{prefix}:attempts:email:#{email}", "#{prefix}:locked:email:#{email}"] if email
  end
  redis.del(*keys) unless keys.empty?
end

cleanup(@redis, ip: @ip, email: @email)
cleanup(@redis, ip: @ip_b, email: @email_b)

## -- Key shape --------------------------------------------------------------

## One request writes the per-IP and per-email counters under the scope prefix
@tester.enforce_email_login_request_rate_limit!(@ip, @email)
[@redis.exists?("email_login_request:attempts:ip:#{@ip}"),
 @redis.exists?("email_login_request:attempts:email:#{@email}")]
#=> [true, true]

## ...and nothing under the reset-request prefix
[@redis.exists?("reset_request:attempts:ip:#{@ip}"),
 @redis.exists?("reset_request:attempts:email:#{@email}")]
#=> [false, false]

## The login is normalized exactly as the reset scope does (same bucket for a
## case/whitespace variant)
@tester.enforce_email_login_request_rate_limit!(nil, "  #{@email.upcase} ")
@redis.get("email_login_request:attempts:email:#{@email}").to_i
#=> 2

## The default scope still builds the historical reset_request keys
@tester.send(:reset_request_ip_keys, '192.0.2.1')
#=> { attempts: 'reset_request:attempts:ip:192.0.2.1', lockout: 'reset_request:locked:ip:192.0.2.1' }

## The registry kinds derive the same keys the scope writes
Onetime::Operations::RateLimit::Registry.keys_for('email_login_request_ip', @ip) ==
  @tester.send(:reset_request_ip_keys, @ip, :email_login_request).values_at(:attempts, :lockout)
#=> true

## -- Separate buckets -------------------------------------------------------

## Locking the email-login IP tier (cap 3) ...
2.times { @tester.enforce_email_login_request_rate_limit!(@ip, "other_#{@tag}@example.com") }
[@redis.exists?("email_login_request:locked:ip:#{@ip}"), @raises.call(@ip, @email_b)]
#=> [true, true]

## ... leaves the reset-request scope open for the same IP
@raises.call(@ip, @email_b, :reset_request)
#=> false

## -- Scope-owned message, verb, tag ----------------------------------------

## The 429 names magic links, not password resets, and reports the scope's cap
begin
  @tester.enforce_email_login_request_rate_limit!(@ip, @email)
  nil
rescue Onetime::LimitExceeded => ex
  [ex.message, ex.max_attempts]
end
#=> ['Too many login link requests. Please try again later.', 3]

## The reset scope keeps its message byte-for-byte
@scopes[:reset_request].message
#=> 'Too many password reset requests. Please try again later.'

## Each scope has its own audit verb; the reset verb is unchanged
[@scopes[:email_login_request].audit_verb, @scopes[:reset_request].audit_verb]
#=> ['auth.email_login_request_throttled', 'auth.reset_request_throttled']

## A cap hit on this scope records the scope's verb in the SECURITY trail
cleanup(@redis, ip: @ip_b, email: @email_b)
set_limit_block(
  'email_login_request_rate_limit',
  'enabled' => true,
  'max_per_ip' => 2,
  'max_per_email' => 50,
  'window' => 900,
  'lockout' => 900,
)
@verb_count = -> { Onetime::ColonelAuditEvent.recent_security(500).count { |ev| ev['verb'] == 'auth.email_login_request_throttled' } }
@before     = @verb_count.call
2.times { @raises.call(@ip_b, @email_b) }
@verb_count.call - @before
#=> 1

## The cap-hit log line carries the scope's tag and names its own env var
captured = []
cleanup(@redis, ip: @ip_b, email: @email_b)
OT.singleton_class.alias_method(:__elr_real_le, :le)
OT.define_singleton_method(:le) { |*msgs, **_payload| captured << msgs.join(' ') }
begin
  allow_hint = Onetime::Application::MiddlewareStack.trusted_proxy_enabled?
  2.times { @tester.enforce_email_login_request_rate_limit!(@ip_b, @email_b) }
ensure
  OT.singleton_class.remove_method(:le)
  OT.singleton_class.alias_method(:le, :__elr_real_le)
  OT.singleton_class.remove_method(:__elr_real_le)
end
line = captured.find { |msg| msg.include?('hit cap') }.to_s
[line.start_with?('[ResetRequestRateLimiter:email_login_request] ip'),
 allow_hint || line.include?('EMAIL_LOGIN_REQUEST_RATE_LIMIT_MAX_PER_IP')]
#=> [true, true]

## The hint names the scope's env var; the default scope keeps the reset one
[@tester.send(:collapsed_ip_tier_hint, 'ip', :email_login_request).include?('EMAIL_LOGIN_REQUEST_RATE_LIMIT_MAX_PER_IP') ||
  Onetime::Application::MiddlewareStack.trusted_proxy_enabled?,
 @tester.send(:collapsed_ip_tier_hint, 'ip').include?('EMAIL_LOGIN_REQUEST')]
#=> [true, false]

## -- Defaults ---------------------------------------------------------------

## With no config block the scope is enabled and uses its own defaults
set_limit_block('email_login_request_rate_limit', nil)
[@tester.send(:reset_request_rate_limit_enabled?, :email_login_request),
 @tester.send(:reset_request_max_per_ip, :email_login_request),
 @tester.send(:reset_request_max_per_email, :email_login_request),
 @tester.send(:reset_request_window, :email_login_request),
 @tester.send(:reset_request_lockout, :email_login_request)]
#=> [true, 30, 90, 3600, 3600]

## Garbage caps fall back to the scope defaults rather than inverting enforcement
set_limit_block(
  'email_login_request_rate_limit',
  'enabled' => true,
  'max_per_ip' => 0,
  'max_per_email' => 'abc',
  'window' => -5,
  'lockout' => 0,
)
[@tester.send(:reset_request_max_per_ip, :email_login_request),
 @tester.send(:reset_request_max_per_email, :email_login_request)]
#=> [30, 90]

## -- One source cannot lock a victim (SEC-B02) ------------------------------

## The shipped caps keep the per-email tier looser than the per-IP tier
@scopes[:email_login_request].default_max_per_email > @scopes[:email_login_request].default_max_per_ip
#=> true

## Under the defaults, one IP that spends its whole budget on one victim locks
## only itself: its own later requests are denied before the email tier counts
## them, so the victim's bucket stops at the per-IP cap
set_limit_block('email_login_request_rate_limit', nil)
@victim    = "victim_#{@tag}@example.com"
@attacker  = '203.0.113.66'
@bystander = '198.51.100.67'
cleanup(@redis, ip: @attacker, email: @victim)
cleanup(@redis, ip: @bystander)
denied     = (1..35).count { @raises.call(@attacker, @victim) }
[denied,
 @redis.exists?("email_login_request:locked:ip:#{@attacker}"),
 @redis.exists?("email_login_request:locked:email:#{@victim}"),
 @redis.get("email_login_request:attempts:email:#{@victim}").to_i]
#=> [5, true, false, 30]

## ...and the victim can still request a link from any other IP
@raises.call(@bystander, @victim)
#=> false

## The reset scope's defaults are unchanged
set_limit_block('reset_request_rate_limit', nil)
[@tester.send(:reset_request_max_per_ip), @tester.send(:reset_request_max_per_email)]
#=> [10, 30]

## -- Independent enable switches --------------------------------------------

## enabled:false on the email-login scope is a no-op for it and writes nothing
@off_ip = '192.0.2.77'
cleanup(@redis, ip: @off_ip, email: @email_b)
set_limit_block('email_login_request_rate_limit', 'enabled' => false, 'max_per_ip' => 1)
set_limit_block('reset_request_rate_limit', 'enabled' => true, 'max_per_ip' => 1, 'max_per_email' => 50)
results = (1..3).map { @raises.call(@off_ip, @email_b) }
[results.none?, @redis.exists?("email_login_request:attempts:ip:#{@off_ip}")]
#=> [true, false]

## ... while the reset scope, still enabled, enforces from the same IP
[@raises.call(@off_ip, @email_b, :reset_request), @raises.call(@off_ip, @email_b, :reset_request)]
#=> [false, true]

## -- Unknown scope ----------------------------------------------------------

## An unknown scope raises KeyError rather than silently sharing a bucket
begin
  @tester.enforce_reset_request_rate_limit!(@ip, @email, scope: :no_such_route)
  :no_error
rescue KeyError
  :key_error
end
#=> :key_error

# Clean up and restore the shared config for later tryout files.
cleanup(@redis, ip: @ip, email: @email)
cleanup(@redis, ip: @ip_b, email: @email_b)
cleanup(@redis, ip: @off_ip, email: @email_b)
cleanup(@redis, email: "other_#{@tag}@example.com")
cleanup(@redis, ip: @attacker, email: @victim)
cleanup(@redis, ip: @bystander)
OT.send(:conf=, @saved_conf)
