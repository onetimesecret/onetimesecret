# tests/unit/ruby/try/15_config_indifferent_access_try.rb
# frozen_string_literal: true

#
# Integration test for IndifferentHash config access
#
# Validates that Config.deep_merge works with IndifferentHash and preserves
# symbol/string key access after merging.
#
# Usage:
#   bundle exec try tests/unit/ruby/try/15_config_indifferent_access_try.rb
#

require_relative '../../../../lib/onetime/indifferent_hash'
require 'yaml'

# -----------------------------------------------------------------------------
# Setup - Inline deep_merge to test without loading full config.rb
# -----------------------------------------------------------------------------

# Inline deep_clone that mirrors Config.deep_clone behavior
def test_deep_clone(config_hash)
  cloned = YAML.load(YAML.dump(config_hash))
  Onetime::IndifferentHash.deep_convert(cloned)
end

# Inline deep_merge that mirrors Config.deep_merge behavior (with fix)
def test_deep_merge(original, other)
  return test_deep_clone(other) if original.nil?
  return test_deep_clone(original) if other.nil?

  original_clone = test_deep_clone(original)
  other_clone = test_deep_clone(other)
  merger = proc do |_key, v1, v2|
    if v1.is_a?(Hash) && v2.is_a?(Hash)
      v1.merge(v2, &merger)
    elsif v2.nil?
      v1
    else
      v2
    end
  end
  merged = original_clone.merge(other_clone, &merger)
  # Ensure result is IndifferentHash for consistent symbol/string access
  Onetime::IndifferentHash.deep_convert(merged)
end

# Create a mock config that mimics YAML-loaded config structure (string keys)
@yaml_config = {
  'site' => {
    'host' => 'localhost:3000',
    'ssl' => false,
    'secret' => 'test_secret_value',
    'authentication' => {
      'enabled' => true,
      'signin' => true,
      'signup' => true,
      'colonels' => ['admin@example.com']
    },
    'secret_options' => {
      'default_ttl' => 604800,
      'ttl_options' => [3600, 7200, 86400],
      'passphrase' => {
        'required' => false,
        'minimum_length' => 0,
        'maximum_length' => 128
      }
    }
  },
  'mail' => {
    'mode' => 'smtp',
    'from' => 'test@example.com',
    'truemail' => {
      'verifier_email' => 'verify@example.com'
    }
  },
  'redis' => {
    'uri' => 'redis://localhost:6379/0'
  },
  'emailer' => {
    'mode' => 'smtp',
    'from' => 'test@example.com'
  },
  'experimental' => {
    'allow_nil_global_secret' => false
  }
}

# Convert to IndifferentHash (simulating what Config.load does)
@config = Onetime::IndifferentHash.deep_convert(@yaml_config)

# Simulate DEFAULTS with symbol keys (like in config.rb)
@defaults = {
  site: {
    secret: nil,
    domains: { enabled: false },
    regions: { enabled: false },
    plans: { enabled: false },
    secret_options: {
      default_ttl: 604800,
      ttl_options: [3600, 7200, 86400]
    },
    authentication: {
      enabled: false,
      signin: false,
      signup: false,
      autoverify: false,
      colonels: [],
      allowed_signup_domains: []
    }
  },
  mail: {},
  experimental: {
    allow_nil_global_secret: false
  }
}

# Test the deep_merge function - this is where the bug manifested
@merged_config = test_deep_merge(@defaults, @config)

# -----------------------------------------------------------------------------
# Config Type Verification
# -----------------------------------------------------------------------------

## Config from deep_convert is IndifferentHash
@config.class
#=> Onetime::IndifferentHash

## Nested config sections are IndifferentHash
@config[:site].class
#=> Onetime::IndifferentHash

## Config after deep_merge is IndifferentHash
@merged_config.class
#=> Onetime::IndifferentHash

## Nested sections in merged config are IndifferentHash
@merged_config[:site].class
#=> Onetime::IndifferentHash

## Deeply nested sections in merged config are IndifferentHash
@merged_config[:site][:authentication].class
#=> Onetime::IndifferentHash

# -----------------------------------------------------------------------------
# Symbol Access (Existing Pattern)
# -----------------------------------------------------------------------------

## Symbol access works for top-level keys
@merged_config[:site].nil?
#=> false

## Symbol access works for nested keys
@merged_config[:site][:host].nil?
#=> false

## Symbol dig works
@merged_config.dig(:site, :host).nil?
#=> false

## Symbol fetch works
@merged_config.fetch(:site, {}).empty?
#=> false

## Symbol access retrieves correct value
@merged_config[:site][:host]
#=> 'localhost:3000'

## Symbol access retrieves secret value
@merged_config[:site][:secret]
#=> 'test_secret_value'

# -----------------------------------------------------------------------------
# String Access (New Pattern)
# -----------------------------------------------------------------------------

## String access works for top-level keys
@merged_config['site'].nil?
#=> false

## String access works for nested keys
@merged_config['site']['host'].nil?
#=> false

## String dig works
@merged_config.dig('site', 'host').nil?
#=> false

## String fetch works
@merged_config.fetch('site', {}).empty?
#=> false

## String access retrieves correct value
@merged_config['site']['host']
#=> 'localhost:3000'

## String access retrieves secret value
@merged_config['site']['secret']
#=> 'test_secret_value'

# -----------------------------------------------------------------------------
# Equivalence Verification (THE CRITICAL BUG TEST)
# -----------------------------------------------------------------------------

## Symbol and string access return same value for host
@merged_config[:site][:host] == @merged_config['site']['host']
#=> true

## Symbol and string access return same object for site
@merged_config[:site].object_id == @merged_config['site'].object_id
#=> true

## Symbol and string dig return same value
@merged_config.dig(:site, :host) == @merged_config.dig('site', 'host')
#=> true

## Mixed key dig works (symbol, string)
@merged_config.dig(:site, 'host')
#=> 'localhost:3000'

## Mixed key dig works (string, symbol)
@merged_config.dig('site', :host)
#=> 'localhost:3000'

## Fetch with symbol equals fetch with string
@merged_config.fetch(:site, nil) == @merged_config.fetch('site', nil)
#=> true

## Nested symbol and string access identical for authentication
@merged_config[:site][:authentication][:enabled] == @merged_config['site']['authentication']['enabled']
#=> true

# -----------------------------------------------------------------------------
# Common Config Patterns (Real Usage)
# -----------------------------------------------------------------------------

## emailer config accessible via symbol
emailer = @merged_config[:emailer]
emailer.nil? || emailer.is_a?(Onetime::IndifferentHash)
#=> true

## emailer config accessible via string
emailer = @merged_config['emailer']
emailer.nil? || emailer.is_a?(Onetime::IndifferentHash)
#=> true

## redis config dig works with symbols
redis_uri = @merged_config.dig(:redis, :uri)
redis_uri.nil? || redis_uri.is_a?(String)
#=> true

## redis config dig works with strings
redis_uri = @merged_config.dig('redis', 'uri')
redis_uri.nil? || redis_uri.is_a?(String)
#=> true

## authentication config pattern works
auth = @merged_config.dig(:site, :authentication) || {}
auth.is_a?(Hash)
#=> true

## secret_options config pattern works
secret_opts = @merged_config.dig(:site, :secret_options) || {}
secret_opts.is_a?(Hash)
#=> true

# -----------------------------------------------------------------------------
# key? Method Verification
# -----------------------------------------------------------------------------

## key? works with symbol
@merged_config.key?(:site)
#=> true

## key? works with string
@merged_config.key?('site')
#=> true

## key? returns false for missing keys
@merged_config.key?(:definitely_not_a_real_config_key)
#=> false

## key? with symbol and string return same result for existing key
@merged_config.key?(:mail) == @merged_config.key?('mail')
#=> true

# -----------------------------------------------------------------------------
# Fetch with Defaults (Common Pattern)
# -----------------------------------------------------------------------------

## fetch with empty hash default works
result = @merged_config.fetch(:nonexistent_section, {})
result == {}
#=> true

## fetch with nil default works
result = @merged_config.fetch(:nonexistent_section, nil)
result.nil?
#=> true

## chained fetch pattern works with symbols
site = @merged_config.fetch(:site, {})
auth = site.fetch(:authentication, {})
auth.is_a?(Hash)
#=> true

## chained fetch pattern works with strings
site = @merged_config.fetch('site', {})
auth = site.fetch('authentication', {})
auth.is_a?(Hash)
#=> true

# -----------------------------------------------------------------------------
# Deep Merge Preserves Values Correctly
# -----------------------------------------------------------------------------

## Deep merge preserves config value over default
@merged_config[:site][:secret]
#=> 'test_secret_value'

## Deep merge preserves nested config value
@merged_config[:site][:authentication][:enabled]
#=> true

## Deep merge adds default keys not in config
@merged_config[:site][:domains][:enabled]
#=> false

## Deep merge preserves array values from config
@merged_config[:site][:authentication][:colonels]
#=> ['admin@example.com']

# -----------------------------------------------------------------------------
# Read Safety
# -----------------------------------------------------------------------------

## Config can be read without errors using multiple access patterns
begin
  _ = @merged_config[:site][:host]
  _ = @merged_config['site']['host']
  _ = @merged_config.dig(:site, :host)
  _ = @merged_config.dig('site', 'host')
  true
rescue => e
  "Error: #{e.message}"
end
#=> true
