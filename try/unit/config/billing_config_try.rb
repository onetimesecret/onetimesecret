# try/unit/config/billing_config_try.rb
#
# frozen_string_literal: true

require_relative '../../../lib/onetime'
require 'fileutils'

# Force BillingConfig to use a non-existent path
# This bypasses the normal file resolution which finds etc/billing.yaml
@original_path = Onetime::BillingConfig.path
Onetime::BillingConfig.path = '/nonexistent/billing.yaml'

# Clear the singleton instance to force fresh load with new path
# Ruby's Singleton module uses @singleton__instance__ internally
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

# Teardown: Restore original path and clear singleton
Onetime::BillingConfig.path = @original_path
Onetime::BillingConfig.instance_variable_set(:@singleton__instance__, nil)
