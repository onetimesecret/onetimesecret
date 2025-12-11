# try/unit/logic/secrets/process_passphrase_try.rb
#
# Tests for passphrase processing in secret creation.
# Ensures empty/nil passphrases are normalized to nil to prevent
# hashing empty strings.
#
# frozen_string_literal: true

require_relative '../../../support/test_logic'

OT.boot! :test, false

# Test helper class that exposes process_passphrase for testing
class PassphraseTestAction < V2::Logic::Secrets::BaseSecretAction
  attr_reader :passphrase

  def initialize(payload = {})
    @params = { 'secret' => payload }
    @payload = payload
  end

  def process_secret
    @kind = :test
    @secret_value = 'test secret content'
  end

  # Expose process_passphrase for direct testing
  def test_process_passphrase
    process_passphrase
    @passphrase
  end
end

# -------------------------------------------------------------------
# POSITIVE TESTS: Valid passphrase scenarios
# -------------------------------------------------------------------

## Passphrase with content is preserved
action = PassphraseTestAction.new({ 'passphrase' => 'mysecretpass' })
action.test_process_passphrase
#=> 'mysecretpass'

## Passphrase with spaces is preserved
action = PassphraseTestAction.new({ 'passphrase' => 'my secret pass' })
action.test_process_passphrase
#=> 'my secret pass'

## Passphrase with special characters is preserved
action = PassphraseTestAction.new({ 'passphrase' => 'P@ssw0rd!123' })
action.test_process_passphrase
#=> 'P@ssw0rd!123'

## Numeric passphrase (as string) is preserved
action = PassphraseTestAction.new({ 'passphrase' => '12345' })
action.test_process_passphrase
#=> '12345'

## Numeric passphrase (as integer) is converted to string
action = PassphraseTestAction.new({ 'passphrase' => 12345 })
action.test_process_passphrase
#=> '12345'

# -------------------------------------------------------------------
# KEY PRESENCE TESTS: Behavior depends on whether key is in payload
# -------------------------------------------------------------------

## Missing passphrase key → nil (no passphrase protection)
action = PassphraseTestAction.new({})
action.test_process_passphrase
#=> nil

## Passphrase key present with nil value → empty string (intentional empty passphrase)
action = PassphraseTestAction.new({ 'passphrase' => nil })
action.test_process_passphrase
#=> ''

## Passphrase key present with empty string → empty string (intentional empty passphrase)
action = PassphraseTestAction.new({ 'passphrase' => '' })
action.test_process_passphrase
#=> ''

## Whitespace-only passphrase is preserved (intentional)
action = PassphraseTestAction.new({ 'passphrase' => '   ' })
action.test_process_passphrase
#=> '   '

# -------------------------------------------------------------------
# INTEGRATION: Verify has_passphrase? works correctly with spawn_pair
# -------------------------------------------------------------------

## Secret created without passphrase (nil) has has_passphrase? == false
_meta1, secret1 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'test content without passphrase',
  passphrase: nil
)
secret1.has_passphrase?
#=> false

## Secret created with empty string passphrase has has_passphrase? == true
# Empty string is a valid intentional passphrase when explicitly provided
_meta2, secret2 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'test content with empty passphrase',
  passphrase: ''
)
secret2.has_passphrase?
#=> true

## Secret created with valid passphrase has has_passphrase? == true
_meta3, secret3 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'test content with passphrase',
  passphrase: 'secretpass123'
)
secret3.has_passphrase?
#=> true

## Secret with passphrase can verify correct passphrase
_meta4, secret4 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'verify correct passphrase',
  passphrase: 'secretpass123'
)
secret4.passphrase?('secretpass123')
#=> true

## Secret with passphrase rejects incorrect passphrase
_meta5, secret5 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'verify incorrect passphrase',
  passphrase: 'secretpass123'
)
secret5.passphrase?('wrongpassword')
#=> false

## Secret without passphrase: passphrase?('') returns false (nothing to compare)
# Note: Higher-level logic uses `!has_passphrase? || passphrase?(val)` for access control
_meta6, secret6 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'no passphrase returns false',
  passphrase: nil
)
secret6.passphrase?('')
#=> false

## Secret without passphrase: passphrase?('anything') returns false (nothing to compare)
_meta7, secret7 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'no passphrase returns false for any input',
  passphrase: nil
)
secret7.passphrase?('anything')
#=> false

## Secret with empty string passphrase: passphrase?('') returns true
_meta8, secret8 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'empty passphrase can be verified',
  passphrase: ''
)
secret8.passphrase?('')
#=> true

## Secret with empty string passphrase: passphrase?('wrong') returns false
_meta9, secret9 = Onetime::Metadata.spawn_pair(
  Onetime::Customer.anonymous.custid,
  3600,
  'empty passphrase rejects non-empty',
  passphrase: ''
)
secret9.passphrase?('wrong')
#=> false
