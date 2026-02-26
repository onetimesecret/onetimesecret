# try/unit/config/billing_config_try.rb
#
# frozen_string_literal: true

require_relative '../../../lib/onetime'
require 'fileutils'

# Test BillingConfig behavior when no config file exists
# We stub ConfigResolver to return a non-existent path
@original_resolve = Onetime::Utils::ConfigResolver.method(:resolve)

# Clear env vars that stripe_key reads before checking config
@original_stripe_api_key = ENV.delete('STRIPE_API_KEY')

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

# --- region accessor tests ---
# Keep the "no billing file" stub active so region reads from empty config

## region returns nil when billing config has no region key
config = Onetime::BillingConfig.instance
config.region
#=> nil

## region returns configured value when region is set in billing.yaml
# Swap stub to a temp YAML containing region: NZ; use a local var in the closure
# to avoid ivar scoping issues with define_singleton_method.
_nz_yaml = File.join(Dir.tmpdir, "billing_region_nz_#{$$}.yaml")
File.write(_nz_yaml, "region: NZ\nenabled: false\n")
_orig = @original_resolve
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve) { |n| n == 'billing' ? _nz_yaml : _orig.call(n) }
Onetime::BillingConfig.instance_variable_set(:@singleton__instance__, nil)
config = Onetime::BillingConfig.instance
result = config.region
FileUtils.rm_f(_nz_yaml)
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve, @original_resolve)
Onetime::BillingConfig.instance_variable_set(:@singleton__instance__, nil)
result
#=> 'NZ'

## region returns nil for empty string in config (treated as unset)
_empty_yaml = File.join(Dir.tmpdir, "billing_region_empty_#{$$}.yaml")
File.write(_empty_yaml, "region: ''\nenabled: false\n")
_orig2 = @original_resolve
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve) { |n| n == 'billing' ? _empty_yaml : _orig2.call(n) }
Onetime::BillingConfig.instance_variable_set(:@singleton__instance__, nil)
config = Onetime::BillingConfig.instance
result = config.region
FileUtils.rm_f(_empty_yaml)
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve, @original_resolve)
Onetime::BillingConfig.instance_variable_set(:@singleton__instance__, nil)
result
#=> nil

# Restore env var cleared in setup
ENV['STRIPE_API_KEY'] = @original_stripe_api_key if @original_stripe_api_key
