# try/unit/models/custom_domain/incoming_secrets_config_try.rb
#
# frozen_string_literal: true

#
# IncomingSecretsConfig Test Suite
# Tests defensive parsing and type coercion for incoming secrets configuration.
#

require_relative '../../../support/test_helpers'

require 'onetime'

OT.boot! :test, false

IncomingSecretsConfig = Onetime::CustomDomain::IncomingSecretsConfig

## Initialize with valid data
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'support@example.com', 'name' => 'Support Team' }
  ],
  'memo_max_length' => 100,
  'default_ttl' => 3600
})
[config.memo_max_length, config.default_ttl, config.recipients.size]
#=> [100, 3600, 1]

## Initialize with nil data uses defaults
config = IncomingSecretsConfig.new(nil)
[config.memo_max_length, config.default_ttl, config.recipients]
#=> [50, 604800, []]

## Initialize with empty hash uses defaults
config = IncomingSecretsConfig.new({})
[config.memo_max_length, config.default_ttl]
#=> [50, 604800]

## Initialize with symbol keys works
config = IncomingSecretsConfig.new({
  memo_max_length: 75,
  default_ttl: 1800
})
[config.memo_max_length, config.default_ttl]
#=> [75, 1800]

## Type coercion: string values converted to integers
config = IncomingSecretsConfig.new({
  'memo_max_length' => '200',
  'default_ttl' => '7200'
})
[config.memo_max_length, config.default_ttl]
#=> [200, 7200]

## Type coercion: nil values fall back to defaults
config = IncomingSecretsConfig.new({
  'memo_max_length' => nil,
  'default_ttl' => nil
})
[config.memo_max_length, config.default_ttl]
#=> [50, 604800]

## Type coercion: zero values fall back to defaults (must be positive)
config = IncomingSecretsConfig.new({
  'memo_max_length' => 0,
  'default_ttl' => 0
})
[config.memo_max_length, config.default_ttl]
#=> [50, 604800]

## Type coercion: negative values fall back to defaults
config = IncomingSecretsConfig.new({
  'memo_max_length' => -50,
  'default_ttl' => -1000
})
[config.memo_max_length, config.default_ttl]
#=> [50, 604800]

## Type coercion: non-numeric strings fall back to defaults
config = IncomingSecretsConfig.new({
  'memo_max_length' => 'invalid',
  'default_ttl' => 'not-a-number'
})
[config.memo_max_length, config.default_ttl]
#=> [50, 604800]

## Type coercion: float values truncated to integer
config = IncomingSecretsConfig.new({
  'memo_max_length' => 75.9,
  'default_ttl' => 3600.5
})
[config.memo_max_length, config.default_ttl]
#=> [75, 3600]

## Defensive parsing: non-Hash entries in recipients array are skipped
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'valid@example.com', 'name' => 'Valid' },
    nil,
    'just a string',
    123,
    ['array', 'element'],
    { 'email' => 'also-valid@example.com', 'name' => 'Also Valid' }
  ]
})
config.recipients.map { |r| r[:email] }
#=> ['valid@example.com', 'also-valid@example.com']

## Defensive parsing: nil names fall back to email local part
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'user@example.com', 'name' => nil }
  ]
})
config.recipients.first[:name]
#=> 'user'

## Defensive parsing: empty string names fall back to email local part
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'support@acme.org', 'name' => '' }
  ]
})
config.recipients.first[:name]
#=> 'support'

## Defensive parsing: whitespace-only names fall back to email local part
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'info@company.io', 'name' => '   ' }
  ]
})
config.recipients.first[:name]
#=> 'info'

## Defensive parsing: numeric name coerced to string
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'user@example.com', 'name' => 12345 }
  ]
})
config.recipients.first[:name]
#=> '12345'

## Defensive parsing: empty recipients array yields empty list
config = IncomingSecretsConfig.new({
  'recipients' => []
})
config.recipients
#=> []

## Defensive parsing: non-array recipients yields empty list
config = IncomingSecretsConfig.new({
  'recipients' => 'not an array'
})
config.recipients
#=> []

## Defensive parsing: nil recipients yields empty list
config = IncomingSecretsConfig.new({
  'recipients' => nil
})
config.recipients
#=> []

## Defensive parsing: entries with empty email are skipped
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => '', 'name' => 'No Email' },
    { 'email' => '   ', 'name' => 'Whitespace Email' },
    { 'email' => 'valid@example.com', 'name' => 'Valid' }
  ]
})
config.recipients.size
#=> 1

## Defensive parsing: entries without email key are skipped
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'name' => 'No Email Key' },
    { 'email' => 'valid@example.com' }
  ]
})
config.recipients.size
#=> 1

## Name truncated to MAX_NAME_LENGTH (100 chars)
long_name = 'A' * 150
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'user@example.com', 'name' => long_name }
  ]
})
config.recipients.first[:name].length
#=> 100

## Email normalized to lowercase and stripped
config = IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => '  User@Example.COM  ', 'name' => 'Test' }
  ]
})
config.recipients.first[:email]
#=> 'user@example.com'

## Recipients limited to MAX_RECIPIENTS (20)
recipients = (1..25).map { |i| { 'email' => "user#{i}@example.com", 'name' => "User #{i}" } }
config = IncomingSecretsConfig.new({ 'recipients' => recipients })
config.recipients.size
#=> 20

## from_json with corrupted JSON returns empty config
config = IncomingSecretsConfig.from_json('{ invalid json }')
[config.memo_max_length, config.default_ttl, config.recipients]
#=> [50, 604800, []]

## from_json with empty string returns empty config
config = IncomingSecretsConfig.from_json('')
[config.memo_max_length, config.default_ttl]
#=> [50, 604800]

## from_json with nil returns empty config
config = IncomingSecretsConfig.from_json(nil)
[config.memo_max_length, config.default_ttl]
#=> [50, 604800]

## from_json with valid JSON parses correctly
json = '{"memo_max_length": 150, "default_ttl": 1800, "recipients": [{"email": "test@example.com", "name": "Test"}]}'
config = IncomingSecretsConfig.from_json(json)
[config.memo_max_length, config.default_ttl, config.recipients.size]
#=> [150, 1800, 1]

## to_json serializes config correctly
config = IncomingSecretsConfig.new({
  'memo_max_length' => 75,
  'default_ttl' => 3600,
  'recipients' => [{ 'email' => 'user@example.com', 'name' => 'User' }]
})
parsed = JSON.parse(config.to_json)
[parsed['memo_max_length'], parsed['default_ttl'], parsed['recipients'].size]
#=> [75, 3600, 1]

## has_incoming_recipients? returns true when recipients exist
config = IncomingSecretsConfig.new({
  'recipients' => [{ 'email' => 'user@example.com', 'name' => 'User' }]
})
config.has_incoming_recipients?
#=> true

## has_incoming_recipients? returns false when no recipients
config = IncomingSecretsConfig.new({})
config.has_incoming_recipients?
#=> false

## set_incoming_recipients replaces recipients
config = IncomingSecretsConfig.new({
  'recipients' => [{ 'email' => 'old@example.com', 'name' => 'Old' }]
})
config.set_incoming_recipients([{ 'email' => 'new@example.com', 'name' => 'New' }])
config.recipients.first[:email]
#=> 'new@example.com'

## clear_incoming_recipients removes all recipients
config = IncomingSecretsConfig.new({
  'recipients' => [{ 'email' => 'user@example.com', 'name' => 'User' }]
})
config.clear_incoming_recipients
config.recipients
#=> []
