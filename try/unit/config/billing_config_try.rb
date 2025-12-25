# try/unit/config/billing_config_try.rb
#
# frozen_string_literal: true

require_relative '../../../lib/onetime'
require 'fileutils'

# Test BillingConfig behavior when no config file exists
# We stub ConfigResolver to return a non-existent path
@original_resolve = Onetime::Utils::ConfigResolver.method(:resolve)

# Stub resolve to return nil for 'billing', forcing empty config
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve) do |name|
  return nil if name == 'billing'
  @original_resolve.call(name)
end

# Clear the singleton instance to force fresh load
Onetime::BillingConfig.instance_variable_set(:@singleton__instance__, nil)

## Can load BillingConfig when file doesn't exist
config = Onetime::BillingConfig.instance
config.config
#=> {}

## enabled? returns false when file doesn't exist
config = Onetime::BillingConfig.instance
config.enabled?
#=> false

## stripe_key returns nil when file doesn't exist
config = Onetime::BillingConfig.instance
config.stripe_key
#=> nil

## webhook_signing_secret returns nil when file doesn't exist
config = Onetime::BillingConfig.instance
config.webhook_signing_secret
#=> nil

## payment_links returns empty hash when file doesn't exist
config = Onetime::BillingConfig.instance
config.payment_links
#=> {}

# Teardown: Restore original method and clear singleton
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve, @original_resolve)
Onetime::BillingConfig.instance_variable_set(:@singleton__instance__, nil)
