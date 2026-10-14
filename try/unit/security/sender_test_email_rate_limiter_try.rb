# try/unit/security/sender_test_email_rate_limiter_try.rb
#
# frozen_string_literal: true

# SenderTestEmailRateLimiter caps "Send test" on a custom domain's email
# sender (POST /api/domains/:extid/email-config/test) per acting customer.
# Every send is a real email through the delivery provider and one row on the
# security audit trail, so the volume is bounded.
#
# The engine (Lua check-and-record, blank-subject refusal, config fallbacks,
# configured-off no-op) is PerCustomerRateLimit's and is covered through the
# SSO policy in sso_diagnostics_rate_limiter_try.rb. This file covers what the
# sender policy declares:
# 1. Its own key prefix and the cap -> LimitExceeded with its message
# 2. Its own bucket, independent of the SSO diagnostics bucket for the same
#    customer
# 3. Cap-hit writes one `domain_sender.test_email_throttled` event to the
#    SECURITY trail
# 4. Its own config block, off under the test config
# 5. The registry row derives the same keys the module writes

require_relative '../../support/test_models'
require 'onetime/security/sender_test_email_rate_limiter'
require 'onetime/security/sso_diagnostics_rate_limiter'
require 'onetime/operations/ratelimit/registry'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

def set_org_feature(key, cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['features'] ||= {}
  new_conf['features']['organizations'] ||= {}
  new_conf['features']['organizations'][key] = cfg
  OT.send(:conf=, new_conf)
end

class SenderTestEmailRateLimiterTester
  include Onetime::Security::SenderTestEmailRateLimiter
  include Onetime::Security::SsoDiagnosticsRateLimiter
end

@tester = SenderTestEmailRateLimiterTester.new
@redis  = Onetime::Customer.dbclient
@policy = Onetime::Security::SenderTestEmailRateLimiter::POLICY

@tag      = "#{Familia.now.to_i}_#{rand(10_000)}"
@customer = "ur1sendertest_#{@tag}"

@raises = lambda do |extid|
  @tester.enforce_sender_test_email_rate_limit!(extid)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, extid)
  redis.del("sender_test_email:attempts:#{extid}", "sender_test_email:locked:#{extid}",
            "sso_diagnostics:attempts:#{extid}", "sso_diagnostics:locked:#{extid}")
end

cleanup(@redis, @customer)

## The test config ships the limiter disabled, so the sender specs are not throttled
Onetime::Security::PerCustomerRateLimit.enabled?(@policy)
#=> false

## With its config block absent it is enabled with the defaults (protective default on)
new_conf = YAML.load(YAML.dump(OT.conf))
new_conf['features']['organizations'].delete('sender_test_email_rate_limit')
OT.send(:conf=, new_conf)
[Onetime::Security::PerCustomerRateLimit.enabled?(@policy),
 Onetime::Security::PerCustomerRateLimit.max_per_customer(@policy)]
#=> [true, Onetime::Security::SenderTestEmailRateLimiter::DEFAULT_MAX_PER_CUSTOMER]

## A send under the cap is allowed and counted under the sender prefix
set_org_feature('sender_test_email_rate_limit',
  'enabled' => true, 'max_per_customer' => 2, 'window' => 900, 'lockout' => 900)
@raises.call(@customer)
@redis.get("sender_test_email:attempts:#{@customer}")
#=> "1"

## The SSO diagnostics bucket for the same customer is untouched
@redis.exists?("sso_diagnostics:attempts:#{@customer}")
#=> false

## The cap-reaching send is allowed and writes ONE security-trail event
@audit_count = -> { Onetime::ColonelAuditEvent.recent_security(500).count { |e| e['verb'] == 'domain_sender.test_email_throttled' && e['actor'] == @customer } }
@admin_before = Onetime::ColonelAuditEvent.count
[@raises.call(@customer), @audit_count.call, Onetime::ColonelAuditEvent.count - @admin_before]
#=> [false, 1, 0]

## The next send raises LimitExceeded with the sender message and the cap
begin
  @tester.enforce_sender_test_email_rate_limit!(@customer)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?, e.message]
end
#=> [2, true, 'Too many test emails. Please try again later.']

## Denied sends write no further events
2.times { @raises.call(@customer) }
@audit_count.call
#=> 1

## The SSO diagnostics limit is a separate budget: the same customer can still run a check
set_org_feature('sso_diagnostics_rate_limit', 'enabled' => true, 'max_per_customer' => 2)
begin
  @tester.enforce_sso_diagnostics_rate_limit!(@customer)
  :allowed
rescue Onetime::LimitExceeded
  :locked
end
#=> :allowed

## The registry row derives exactly the keys the module writes
Onetime::Operations::RateLimit::Registry.keys_for('sender_test_email', @customer)
#=> ["sender_test_email:attempts:#{@customer}", "sender_test_email:locked:#{@customer}"]

## ...on the Customer shard, matching the engine's accessor
Onetime::Operations::RateLimit::Registry.fetch('sender_test_email')[:dbclient].call.equal?(Onetime::Security::PerCustomerRateLimit.redis)
#=> true

# Teardown: restore the booted config for later tryout files and clear keys.
cleanup(@redis, @customer)
OT.send(:conf=, @saved_conf)
