# try/integration/email/mailer_sender_config_try.rb
#
# frozen_string_literal: true

# Integration tests for Mailer with per-domain sender_config.
#
# Verifies that:
#   - Mailer.deliver with an enabled+verified sender_config uses custom from_address
#   - Mailer.deliver_raw with sender_config uses custom from_address
#   - Nil/disabled/unverified sender_config falls back to global defaults
#
# Uses a capturing backend that records the normalized email hash,
# allowing assertions on the actual from/reply_to values passed to delivery.

require_relative '../../support/test_helpers'

ENV['EMAILER_MODE'] = 'logger'

OT.boot! :test, false

require 'onetime/mail'

Onetime::Config.load

# A test backend that captures the last delivered email for inspection.
# Inherits from Base so normalize_email and deliver flow work correctly.
class CapturingBackend < Onetime::Mail::Delivery::Base
  attr_reader :last_email

  def perform_delivery(email)
    @last_email = email
    { status: 'captured', to: email[:to], from: email[:from] }
  end

  def delivery_log_status
    'captured'
  end
end

@capturing_backend = CapturingBackend.new

# Override delivery_backend to return our capturing backend
Onetime::Mail::Mailer.reset!
Onetime::Mail::Mailer.define_singleton_method(:delivery_backend) { @capturing_backend ||= CapturingBackend.new }
# Inject our specific instance
Onetime::Mail::Mailer.instance_variable_set(:@capturing_backend, @capturing_backend)

# Also need to handle resolve_backend for domain backends. The capturing backend
# will be returned by resolve_backend when sender_config is not enabled/verified
# (falls through to delivery_backend). For enabled+verified configs, Mailer
# creates a per-domain backend via create_backend_for. Since MockSenderConfig
# uses provider: 'logger', it will create a Logger backend. We override
# create_backend_for to return our capturing backend for test domains.
original_create_backend_for = Onetime::Mail::Mailer.method(:create_backend_for)
Onetime::Mail::Mailer.define_singleton_method(:create_backend_for) do |sender_config|
  @capturing_backend
end

# Mock sender config using a simple struct to avoid Redis dependencies.
MockSenderConfig = Struct.new(
  :domain_id, :from_address, :from_name, :reply_to,
  :provider, :api_key, :enabled_val, :verified_val,
  keyword_init: true
) do
  def enabled?
    enabled_val == true
  end

  def verified?
    verified_val == true
  end
end

@enabled_config = MockSenderConfig.new(
  domain_id: 'dom_tryout_001',
  from_address: 'custom-sender@acme.example.com',
  from_name: 'Acme Secrets',
  reply_to: 'support@acme.example.com',
  provider: 'logger',
  api_key: nil,
  enabled_val: true,
  verified_val: true
)

@disabled_config = MockSenderConfig.new(
  domain_id: 'dom_tryout_002',
  from_address: 'disabled@acme.example.com',
  from_name: 'Disabled Sender',
  reply_to: nil,
  provider: 'logger',
  api_key: nil,
  enabled_val: false,
  verified_val: true
)

@unverified_config = MockSenderConfig.new(
  domain_id: 'dom_tryout_003',
  from_address: 'unverified@acme.example.com',
  from_name: 'Unverified Sender',
  reply_to: nil,
  provider: 'logger',
  api_key: nil,
  enabled_val: true,
  verified_val: false
)

@recipient = 'tryouts+recipient@onetimesecret.com'
@sender = 'tryouts+sender@onetimesecret.com'
@global_from = Onetime::Mail::Mailer.from_address

# TRYOUTS

## deliver with enabled+verified sender_config uses custom from_address
Onetime::Mail::Mailer.deliver(:secret_link, {
  secret_key: 'sender_config_test_key',
  recipient: @recipient,
  sender_email: @sender
}, sender_config: @enabled_config)
@capturing_backend.last_email[:from]
#=> 'custom-sender@acme.example.com'

## deliver with enabled+verified sender_config uses custom reply_to
Onetime::Mail::Mailer.deliver(:secret_link, {
  secret_key: 'reply_to_test_key',
  recipient: @recipient,
  sender_email: @sender
}, sender_config: @enabled_config)
@capturing_backend.last_email[:reply_to]
#=> 'support@acme.example.com'

## deliver with nil sender_config uses global from_address
Onetime::Mail::Mailer.deliver(:secret_link, {
  secret_key: 'global_fallback_test',
  recipient: @recipient,
  sender_email: @sender
}, sender_config: nil)
@capturing_backend.last_email[:from]
#=> @global_from

## deliver with disabled sender_config uses global from_address
Onetime::Mail::Mailer.deliver(:secret_link, {
  secret_key: 'disabled_test',
  recipient: @recipient,
  sender_email: @sender
}, sender_config: @disabled_config)
@capturing_backend.last_email[:from]
#=> @global_from

## deliver with unverified sender_config uses global from_address
Onetime::Mail::Mailer.deliver(:secret_link, {
  secret_key: 'unverified_test',
  recipient: @recipient,
  sender_email: @sender
}, sender_config: @unverified_config)
@capturing_backend.last_email[:from]
#=> @global_from

## deliver_raw with sender_config uses custom from_address
Onetime::Mail::Mailer.deliver_raw({
  to: @recipient,
  from: 'original@example.com',
  subject: 'Raw with sender_config',
  body: 'Test body'
}, sender_config: @enabled_config)
@capturing_backend.last_email[:from]
#=> 'custom-sender@acme.example.com'

## deliver_raw with nil sender_config preserves original from
Onetime::Mail::Mailer.deliver_raw({
  to: @recipient,
  from: 'original@example.com',
  subject: 'Raw without sender_config',
  body: 'Test body'
}, sender_config: nil)
@capturing_backend.last_email[:from]
#=> 'original@example.com'

## deliver_raw with disabled sender_config preserves original from
Onetime::Mail::Mailer.deliver_raw({
  to: @recipient,
  from: 'original@example.com',
  subject: 'Raw disabled config',
  body: 'Test body'
}, sender_config: @disabled_config)
@capturing_backend.last_email[:from]
#=> 'original@example.com'

## deliver_raw with sender_config uses custom reply_to
Onetime::Mail::Mailer.deliver_raw({
  to: @recipient,
  from: 'original@example.com',
  reply_to: 'original-reply@example.com',
  subject: 'Raw reply_to override',
  body: 'Test body'
}, sender_config: @enabled_config)
@capturing_backend.last_email[:reply_to]
#=> 'support@acme.example.com'

## deliver with sender_config still delivers to correct recipient
Onetime::Mail::Mailer.deliver(:secret_link, {
  secret_key: 'recipient_test',
  recipient: @recipient,
  sender_email: @sender
}, sender_config: @enabled_config)
@capturing_backend.last_email[:to]
#=> @recipient
