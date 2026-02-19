# try/features/incoming/incoming_config_try.rb
#
# frozen_string_literal: true

# These tryouts test the incoming secrets configuration and recipient handling.
# They verify:
# 1. Feature configuration loading from config
# 2. Recipient lookup via hash
# 3. Public recipients list generation (without email exposure)

require_relative '../../support/test_models'
OT.boot! :test, false

# Load the lib-level setup_incoming_recipients initializer so OT gains the
# setup_incoming_recipients module method (it is not auto-required by the core
# initializers.rb — the v3 app auto-discovers it separately).
require 'onetime/initializers/setup_incoming_recipients'

# Test recipient configuration from DEFAULTS
# Note: In actual deployment, recipients would be configured in config.yaml

## Incoming feature is disabled by default
config = OT.conf.dig('features', 'incoming')
config['enabled']
#=> false

## Default memo max length is 50
config = OT.conf.dig('features', 'incoming')
config['memo_max_length']
#=> 50

## Default TTL is 7 days (604800 seconds)
config = OT.conf.dig('features', 'incoming')
config['default_ttl']
#=> 604_800

## Default recipients list is empty
config = OT.conf.dig('features', 'incoming')
config['recipients']
#=> []

## Public recipients list is empty by default (no initializer run)
OT.incoming_public_recipients
#=> []

## Recipient lookup returns nil for unknown hash
OT.lookup_incoming_recipient('unknown_hash_123')
#=> nil

## Can access memo field on Receipt model
receipt = Onetime::Receipt.new
receipt.memo = 'Test memo'
receipt.memo
#=> 'Test memo'

# Guard: setup_incoming_recipients raises OT::Problem when site.secret is nil
# Requires feature to be enabled to reach the guard.
# Save original config before mutating so we can restore it in ensure.

## setup_incoming_recipients raises OT::Problem when site.secret is nil
@_saved_conf_nil = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(@_saved_conf_nil))
  conf_copy['features']['incoming']['enabled'] = true
  conf_copy['site'].delete('secret')
  OT.send(:conf=, conf_copy)
  OT.setup_incoming_recipients
  false
rescue OT::Problem => e
  e.message.include?('site.secret')
rescue => e
  e.class.name
ensure
  OT.send(:conf=, @_saved_conf_nil) rescue nil
end
#=> true

## setup_incoming_recipients raises OT::Problem when site.secret is blank whitespace
@_saved_conf_blank = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(@_saved_conf_blank))
  conf_copy['features']['incoming']['enabled'] = true
  conf_copy['site']['secret'] = '   '
  OT.send(:conf=, conf_copy)
  OT.setup_incoming_recipients
  false
rescue OT::Problem => e
  e.message.include?('site.secret')
rescue => e
  e.class.name
ensure
  OT.send(:conf=, @_saved_conf_blank) rescue nil
end
#=> true

# Whitespace normalization: email with leading/trailing spaces produces the same
# hash as the trimmed email, ensuring the lookup table entry is consistent.

## Email with surrounding whitespace is stripped before hashing
@_saved_conf_ws = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(@_saved_conf_ws))
  conf_copy['features']['incoming']['enabled'] = true
  conf_copy['features']['incoming']['recipients'] = [
    { 'email' => '  alice@example.com  ', 'name' => 'Alice' }
  ]
  OT.send(:conf=, conf_copy)
  OT.setup_incoming_recipients
  # The lookup should use the trimmed email, not the padded one
  OT.incoming_recipient_lookup.values.first
ensure
  OT.send(:conf=, @_saved_conf_ws) rescue nil
  OT.instance_variable_set(:@incoming_recipient_lookup, {}.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [].freeze)
end
#=> 'alice@example.com'

## Recipient with blank email is silently skipped
@_saved_conf_blank_email = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(@_saved_conf_blank_email))
  conf_copy['features']['incoming']['enabled'] = true
  conf_copy['features']['incoming']['recipients'] = [
    { 'email' => '   ', 'name' => 'Blank' },
    { 'email' => 'valid@example.com', 'name' => 'Valid' }
  ]
  OT.send(:conf=, conf_copy)
  OT.setup_incoming_recipients
  # Only the valid recipient should be in the lookup
  OT.incoming_recipient_lookup.size
ensure
  OT.send(:conf=, @_saved_conf_blank_email) rescue nil
  OT.instance_variable_set(:@incoming_recipient_lookup, {}.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [].freeze)
end
#=> 1

## Recipient name with surrounding whitespace is stripped
@_saved_conf_name_ws = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(@_saved_conf_name_ws))
  conf_copy['features']['incoming']['enabled'] = true
  conf_copy['features']['incoming']['recipients'] = [
    { 'email' => 'bob@example.com', 'name' => '  Bob Smith  ' }
  ]
  OT.send(:conf=, conf_copy)
  OT.setup_incoming_recipients
  OT.incoming_public_recipients.first[:name]
ensure
  OT.send(:conf=, @_saved_conf_name_ws) rescue nil
  OT.instance_variable_set(:@incoming_recipient_lookup, {}.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [].freeze)
end
#=> 'Bob Smith'
