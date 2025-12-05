# try/unit/config/billing_config_try.rb
#
# frozen_string_literal: true

require_relative '../../../lib/onetime'
require 'fileutils'

# Backup existing billing config if it exists
@billing_config_path = File.expand_path('../../../etc/billing.yaml', __dir__)
@billing_config_backup = nil
if File.exist?(@billing_config_path)
  @billing_config_backup = File.read(@billing_config_path)
  FileUtils.mv(@billing_config_path, "#{@billing_config_path}.bak")
end

# Clear the singleton instance
Onetime::BillingConfig.instance_variable_set(:@instance, nil)

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

# Teardown: Restore billing config if it existed
if @billing_config_backup
  FileUtils.mv("#{@billing_config_path}.bak", @billing_config_path)
end
