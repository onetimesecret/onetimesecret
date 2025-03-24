# frozen_string_literal: true

# These tests cover the Secrets logic classes which handle
# the core secret management functionality of the application.
#
# We test:
# 1. Secret creation (ConcealSecret)
# 2. Secret viewing (ShowSecret, RevealSecret)
# 3. Secret metadata (ShowMetadata, ShowMetadataList)
# 4. Secret deletion (BurnSecret)

require_relative '../test_helpers'

# Load the app with test configuration
OT.boot! :test

# Setup common test variables
@now = DateTime.now
@email = 'test@onetimesecret.com'
@sess = OT::Session.new '255.255.255.255', 'anon'
@cust = OT::Customer.new @email
@cust.save
@secret = OT::Secret.new
@secret.generate_id
@metadata = OT::Metadata.new
@metadata.generate_id

# ConcealSecret Tests

## New secrets have a nil key
secret = OT::Secret.new
secret.key
#=> nil

## New secrets only get a key when we give them one
secret = OT::Secret.new
secret.generate_id
[secret.key.is_a?(String), secret.key.length > 16]
#=> [true, true]

## Test basic secret creation
@secret_params = {
  secret: 'test secret value',
  passphrase: 'testpass123',
  ttl: '7200',
  recipient: 'recipient@example.com'
}
logic = OT::Logic::Secrets::ConcealSecret.new @sess, @cust, {secret: @secret_params}
[
  logic.secret_value,
  logic.passphrase,
  logic.ttl,
  logic.recipient,
  logic.recipient_safe,
]
#=> ['test secret value', 'testpass123', 7200, ['recipient@example.com'], ["re*****@e*****.com"]]

# ShowSecret Tests

## Create a secret for viewing tests
@secret.value = 'test secret'
@secret.passphrase = 'testpass123'
@secret.save

# Test secret viewing
@view_params = {
  key: @secret.key, # Key converted to symbol
  passphrase: 'testpass123' # Key converted to symbol
}
logic = OT::Logic::Secrets::ShowSecret.new @sess, @cust, @view_params
[logic.key, logic.passphrase]
#=> [@secret.key, 'testpass123']

# RevealSecret Tests

## Test secret revealing (v2 API)
logic = OT::Logic::Secrets::RevealSecret.new @sess, @cust, @view_params
[logic.key, logic.passphrase]
#=> [@secret.key, 'testpass123']

# ShowMetadata Tests

## Test metadata viewing
logic = OT::Logic::Secrets::ShowMetadata.new @sess, @cust, { key: @metadata.key }
[logic.instance_variables.include?(:@key), logic.instance_variables.include?(:@metadata_key), logic.instance_variables.include?(:@secret_key), logic.secret_key, logic.key]
#=> [true, false, false, nil, @metadata.key]

# ShowMetadataList Tests

## Note that process_params is not run unless params are passed in
logic = OT::Logic::Secrets::ShowMetadataList.new @sess, @cust
[logic.since, logic.now]
#=> [nil, nil]

## Test metadata list viewing
logic = OT::Logic::Secrets::ShowMetadataList.new @sess, @cust, {}
[logic.records.class, logic.since.class, logic.now.class]
#=> [NilClass, Integer, Time]

# BurnSecret Tests

## Test secret burning
logic = OT::Logic::Secrets::BurnSecret.new @sess, @cust, @view_params
[logic.key, logic.passphrase]
#=> [@secret.key, 'testpass123']

# Cleanup test data
@cust.delete!
@secret.delete!
@metadata.delete!
