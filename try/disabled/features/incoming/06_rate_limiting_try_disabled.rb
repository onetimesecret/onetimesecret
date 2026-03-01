# try/features/incoming/06_rate_limiting_try.rb
#
# frozen_string_literal: true

# Rate Limiting Spec — spec-before-implement
#
# These tryouts document the intended rate-limiting behaviour for V3 incoming
# endpoints. They are expected to FAIL until rate limiting is added to the
# raise_concerns methods in:
#   apps/api/v3/logic/incoming/create_incoming_secret.rb
#   apps/api/v3/logic/incoming/get_config.rb
#
# Intended behaviour (ported from v0.23 PR #2538):
#   - CreateIncomingSecret#raise_concerns calls limit_action :create_secret
#   - CreateIncomingSecret#raise_concerns calls limit_action :email_recipient
#   - GetConfig#raise_concerns calls limit_action :get_page
#   - When a limit is exceeded, OT::LimitExceeded is raised before the request
#     proceeds to update_customer_stats or send_recipient_notification

require_relative '../../support/test_logic'
require 'apps/api/v3/logic'

OT.boot! :test, false

@email = "tryouts+ratelimit+#{Familia.now.to_i}@onetimesecret.com"
@cust = Onetime::Customer.create!(email: @email)
@strategy_result = MockStrategyResult.new(session: {}, user: @cust)

@test_recipient_email = "recipient+ratelimit+#{Familia.now.to_i}@onetimesecret.com"
@test_recipient_hash  = 'ratelimit_recipient_hash_abc123'

@original_conf = YAML.load(YAML.dump(OT.conf))

def enable_incoming_feature_rl(recipient_hash, recipient_email)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['features']['incoming']['enabled'] = true
  OT.send(:conf=, new_conf)
  OT.instance_variable_set(:@incoming_recipient_lookup, {
    recipient_hash => recipient_email
  }.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [
    { hash: recipient_hash, name: 'Rate Limit Test Recipient' }
  ].freeze)
end

def disable_incoming_feature_rl(original_conf)
  OT.send(:conf=, original_conf)
  OT.instance_variable_set(:@incoming_recipient_lookup, {}.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [].freeze)
end

# ---------------------------------------------------------------------------
# CreateIncomingSecret rate-limiting (spec-before-implement)
# ---------------------------------------------------------------------------
# The raise_concerns method should call limit_action :create_secret.
# Currently there is no limit_action call so this spy test will fail.

## CreateIncomingSecret raise_concerns calls limit_action :create_secret
# NOTE: expected to FAIL until rate limiting is implemented in V3
enable_incoming_feature_rl(@test_recipient_hash, @test_recipient_email)
limit_actions_called = []
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo'      => 'Rate limit test memo',
    'secret'    => 'Rate limit test secret',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
# Spy: capture limit_action calls via singleton override
logic.define_singleton_method(:limit_action) { |action| limit_actions_called << action }
logic.raise_concerns
limit_actions_called.include?(:create_secret)
#=> true

## CreateIncomingSecret raise_concerns calls limit_action :email_recipient
# NOTE: expected to FAIL until rate limiting is implemented in V3
enable_incoming_feature_rl(@test_recipient_hash, @test_recipient_email)
limit_actions_called2 = []
logic2 = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo'      => 'Rate limit test memo',
    'secret'    => 'Rate limit test secret',
    'recipient' => @test_recipient_hash
  }
})
logic2.process_params
logic2.define_singleton_method(:limit_action) { |action| limit_actions_called2 << action }
logic2.raise_concerns
limit_actions_called2.include?(:email_recipient)
#=> true

# ---------------------------------------------------------------------------
# GetConfig rate-limiting (spec-before-implement)
# ---------------------------------------------------------------------------
# The raise_concerns method should call limit_action :get_page.

## GetConfig raise_concerns calls limit_action :get_page
# NOTE: expected to FAIL until rate limiting is implemented in V3
enable_incoming_feature_rl(@test_recipient_hash, @test_recipient_email)
limit_actions_called3 = []
config_logic = V3::Logic::Incoming::GetConfig.new(@strategy_result, {})
config_logic.process_params
config_logic.define_singleton_method(:limit_action) { |action| limit_actions_called3 << action }
config_logic.raise_concerns
limit_actions_called3.include?(:get_page)
#=> true

# ---------------------------------------------------------------------------
# OT::LimitExceeded propagates from raise_concerns (spec-before-implement)
# ---------------------------------------------------------------------------
# When limit_action raises OT::LimitExceeded, it should propagate out of
# raise_concerns without being swallowed.

## CreateIncomingSecret propagates OT::LimitExceeded from limit_action
# NOTE: expected to FAIL until rate limiting is implemented in V3
enable_incoming_feature_rl(@test_recipient_hash, @test_recipient_email)
begin
  limit_logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
    'secret' => {
      'memo'      => 'Over-limit test',
      'secret'    => 'Over-limit secret content',
      'recipient' => @test_recipient_hash
    }
  })
  limit_logic.process_params
  # Simulate limit_action raising as if the rate limit is exceeded
  limit_logic.define_singleton_method(:limit_action) do |_action|
    raise OT::LimitExceeded, 'Rate limit exceeded'
  end
  limit_logic.raise_concerns
  false # should not reach here
rescue OT::LimitExceeded
  true
rescue NameError
  # OT::LimitExceeded not defined yet — also documents the gap
  :not_implemented
end
#=> true

## Cleanup
disable_incoming_feature_rl(@original_conf)
@cust.destroy! if @cust
true
#=> true
