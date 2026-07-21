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

# --- checkout_host validation ---
# checkout_host reads ENV['STRIPE_CHECKOUT_HOST'] first, so drive it via ENV.
@original_checkout_host = ENV.delete('STRIPE_CHECKOUT_HOST')

## valid_checkout_host? is true when unset (feature off)
Onetime::BillingConfig.instance.valid_checkout_host?
#=> true

## validate_checkout_host! is a no-op when unset
Onetime::BillingConfig.instance.validate_checkout_host!
#=> nil

## valid_checkout_host? accepts a bare host
ENV['STRIPE_CHECKOUT_HOST'] = 'pay.onetimesecret.com'
Onetime::BillingConfig.instance.valid_checkout_host?
#=> true

## valid_checkout_host? accepts a bare host with a port
ENV['STRIPE_CHECKOUT_HOST'] = 'pay.onetimesecret.com:8443'
Onetime::BillingConfig.instance.valid_checkout_host?
#=> true

## valid_checkout_host? rejects a scheme prefix
ENV['STRIPE_CHECKOUT_HOST'] = 'https://pay.onetimesecret.com'
Onetime::BillingConfig.instance.valid_checkout_host?
#=> false

## valid_checkout_host? rejects an embedded path
ENV['STRIPE_CHECKOUT_HOST'] = 'pay.onetimesecret.com/checkout'
Onetime::BillingConfig.instance.valid_checkout_host?
#=> false

## valid_checkout_host? rejects userinfo (origin-selection attack)
ENV['STRIPE_CHECKOUT_HOST'] = 'pay.onetimesecret.com@evil.example'
Onetime::BillingConfig.instance.valid_checkout_host?
#=> false

## validate_checkout_host! raises ConfigError on a malformed host
ENV['STRIPE_CHECKOUT_HOST'] = 'https://pay.onetimesecret.com'
begin
  Onetime::BillingConfig.instance.validate_checkout_host!
  :no_raise
rescue Onetime::ConfigError
  :raised
end
#=> :raised

# Restore checkout_host env var
ENV.delete('STRIPE_CHECKOUT_HOST')
ENV['STRIPE_CHECKOUT_HOST'] = @original_checkout_host unless @original_checkout_host.nil?

# Restore env var cleared in setup
ENV['STRIPE_API_KEY'] = @original_stripe_api_key unless @original_stripe_api_key.nil?
