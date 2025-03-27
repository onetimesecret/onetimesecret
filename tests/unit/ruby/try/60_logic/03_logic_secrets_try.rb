# tests/unit/ruby/try/60_logic/03_logic_secrets_try.rb

# These tests cover the Secrets logic classes which handle
# the core secret management functionality of the application.
#
# We test:
# 1. Secret creation (ConcealSecret)
# 2. Secret viewing (ShowSecret, RevealSecret)
# 3. Secret metadata (ShowMetadata, ShowMetadataList)
# 4. Secret deletion (BurnSecret)

require_relative '../test_logic'

# Load the app with test configuration
OT.boot! :test, false

# Setup common test variables
@now = DateTime.now
@email = 'test@onetimesecret.com'
@sess = Session.new '255.255.255.255', 'anon'
@cust = Customer.new @email
@cust.save
@secret = Secret.new
@secret.generate_id
@metadata = Metadata.new
@metadata.generate_id

# ConcealSecret Tests

## New secrets have a nil key
secret = Secret.new
secret.key
#=> nil

## New secrets only get a key when we give them one
secret = Secret.new
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
logic = Logic::Secrets::ConcealSecret.new @sess, @cust, {secret: @secret_params}
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
logic = Logic::Secrets::ShowSecret.new @sess, @cust, @view_params
[logic.key, logic.passphrase]
#=> [@secret.key, 'testpass123']

# RevealSecret Tests

## Test secret revealing (v2 API)
logic = Logic::Secrets::RevealSecret.new @sess, @cust, @view_params
[logic.key, logic.passphrase]
#=> [@secret.key, 'testpass123']

# ShowMetadata Tests

## Test metadata viewing
logic = Logic::Secrets::ShowMetadata.new @sess, @cust, { key: @metadata.key }
[logic.instance_variables.include?(:@key), logic.instance_variables.include?(:@metadata_key), logic.instance_variables.include?(:@secret_key), logic.secret_key, logic.key]
#=> [true, false, false, nil, @metadata.key]

# ShowMetadataList Tests

## Note that process_params is not run unless params are passed in
logic = Logic::Secrets::ShowMetadataList.new @sess, @cust
[logic.since, logic.now]
#=> [nil, nil]

## Test metadata list viewing
logic = Logic::Secrets::ShowMetadataList.new @sess, @cust, {}
[logic.records.class, logic.since.class, logic.now.class]
#=> [NilClass, Integer, Time]

# BurnSecret Tests

## Test secret burning
logic = Logic::Secrets::BurnSecret.new @sess, @cust, @view_params
[logic.key, logic.passphrase]
#=> [@secret.key, 'testpass123']

# Cleanup test data
@cust.delete!
@secret.delete!
@metadata.delete!
