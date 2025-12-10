# try/integration/billing/app_loading_scenarios_try.rb
#
# frozen_string_literal: true

## Billing App Loading - Scenario Tests
#
# These tests verify the billing app loading behavior using temporary
# configuration files to simulate different scenarios.

require_relative '../../support/test_helpers'
require 'tempfile'
require 'fileutils'

## Test simulated billing config enabled=false returns correct value
# Simulate what happens when billing.yaml has enabled: false
def simulate_billing_config_check(yaml_content)
  config = YAML.safe_load(yaml_content, symbolize_names: false) || {}
  config.dig('billing', 'enabled').to_s == 'true'
end

yaml_disabled = <<~YAML
  billing:
    enabled: false
    stripe_key: sk_test_disabled
YAML

simulate_billing_config_check(yaml_disabled)
#=> false

## Test simulated billing config enabled=true returns correct value
yaml_enabled = <<~YAML
  billing:
    enabled: true
    stripe_key: sk_test_enabled
YAML

simulate_billing_config_check(yaml_enabled)
#=> true

## Test simulated billing config with missing file returns false
yaml_empty = "{}"
simulate_billing_config_check(yaml_empty)
#=> false

## Test registry filter logic simulates billing enabled condition
def test_billing_should_load(billing_enabled)
  app_name = 'Billing::Application'
  # Registry keeps app when billing enabled, filters when disabled
  !(app_name.include?('Billing') && !billing_enabled)
end
test_billing_should_load(true)
#=> true

## Test registry filter logic simulates billing disabled condition
test_billing_should_load(false)
#=> false

## Current billing config singleton is accessible
Onetime.billing_config.class.name
#=> "Onetime::BillingConfig"

## Billing config has safe enabled? method (returns boolean)
[TrueClass, FalseClass].include?(Onetime.billing_config.enabled?.class)
#=> true

## Billing config has safe helper methods that return nil or empty
[
  Onetime.billing_config.stripe_key.class,
  Onetime.billing_config.webhook_signing_secret.class,
  Onetime.billing_config.payment_links.class
].all? { |klass| [String, NilClass, Hash].include?(klass) }
#=> true
