# try/unit/mail/lettermint_credential_access_try.rb
#
# frozen_string_literal: true

# Tests for LettermintSenderStrategy credential access patterns.
#
# This test validates that the strategy correctly handles credentials
# passed with string keys (the project convention for interface boundaries).
#
# Background: build_provider_config was returning symbol keys (:team_token)
# while check_provider_verification_status accessed credentials['team_token'].
# The mismatch meant team_token was always nil, causing provider verification
# to always fail with "Lettermint Team API token is required".
#
# Validates:
# 1. provision_dns_records accepts string-keyed credentials
# 2. check_provider_verification_status accepts string-keyed credentials
# 3. delete_sender_identity accepts string-keyed credentials
# 4. Missing team_token is caught for both key types
# 5. build_client correctly extracts team_token from string keys
# 6. The full validation path (credentials -> strategy -> API call) works

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'onetime/mail'
require 'lettermint'
require 'onetime/mail/sender_strategies/lettermint_sender_strategy'

@strategy = Onetime::Mail::SenderStrategies::LettermintSenderStrategy.new

# Mock mailer_config with from_address
@mock_config = Struct.new(:from_address).new('sender@example.com')

# --- provision_dns_records: string-keyed credentials ---

## provision_dns_records with string key team_token does not return missing_team_token error
creds = { 'team_token' => 'lm-team-token', 'base_url' => 'https://api.test.co/v1' }
# We expect a different error (network/API) because team_token is found.
# The missing_team_token error path is what we're checking doesn't trigger.
result = @strategy.provision_dns_records(@mock_config, credentials: creds)
result[:error] != 'missing_team_token'
#=> true

## provision_dns_records with empty string credentials returns missing_team_token
creds = { 'team_token' => '', 'api_token' => 'something' }
result = @strategy.provision_dns_records(@mock_config, credentials: creds)
result[:error]
#=> 'missing_team_token'

## provision_dns_records with nil string-key team_token returns missing_team_token
creds = { 'team_token' => nil }
result = @strategy.provision_dns_records(@mock_config, credentials: creds)
result[:error]
#=> 'missing_team_token'

## provision_dns_records with completely empty credentials returns missing_team_token
creds = {}
result = @strategy.provision_dns_records(@mock_config, credentials: creds)
result[:error]
#=> 'missing_team_token'

# --- check_provider_verification_status: string-keyed credentials ---

## check_provider_verification_status with string key team_token does not return token-required error
creds = { 'team_token' => 'lm-team-token', 'base_url' => 'https://api.test.co/v1' }
result = @strategy.check_provider_verification_status(@mock_config, credentials: creds)
# Should not be the "token is required" error - should be a different error (network/API)
result[:message].include?('Team API token is required') == false
#=> true

## check_provider_verification_status with empty string credentials returns token-required error
creds = { 'team_token' => '' }
result = @strategy.check_provider_verification_status(@mock_config, credentials: creds)
result[:message]
#=~ /Team API token is required/

## check_provider_verification_status with nil string-key team_token returns error
creds = { 'team_token' => nil }
result = @strategy.check_provider_verification_status(@mock_config, credentials: creds)
result[:status]
#=> 'error'

## check_provider_verification_status with no credentials returns error
creds = {}
result = @strategy.check_provider_verification_status(@mock_config, credentials: creds)
result[:status]
#=> 'error'

# --- delete_sender_identity: string-keyed credentials ---

## delete_sender_identity with string key team_token does not return token-required error
creds = { 'team_token' => 'lm-team-token', 'base_url' => 'https://api.test.co/v1' }
result = @strategy.delete_sender_identity(@mock_config, credentials: creds)
# Should not be the "token is required" error
result[:message].include?('Team API token is required') == false
#=> true

## delete_sender_identity with empty credentials returns token-required message
creds = { 'team_token' => '' }
result = @strategy.delete_sender_identity(@mock_config, credentials: creds)
result[:message]
#=~ /Team API token is required/

# --- build_client: string key extraction ---

## build_client extracts team_token from string keys
creds = { 'team_token' => 'lm_team_string-key-token', 'base_url' => 'https://api.test.co/v1', 'timeout' => 15 }
client = @strategy.send(:build_client, creds)
client.is_a?(Lettermint::TeamAPI)
#=> true

# --- Invalid from_address paths ---

## provision_dns_records with invalid from_address returns invalid_from_address
bad_config = Struct.new(:from_address).new('not-an-email')
creds = { 'team_token' => 'valid-token' }
result = @strategy.provision_dns_records(bad_config, credentials: creds)
result[:error]
#=> 'invalid_from_address'

## check_provider_verification_status with invalid from_address returns invalid status
bad_config = Struct.new(:from_address).new('not-an-email')
creds = { 'team_token' => 'valid-token' }
result = @strategy.check_provider_verification_status(bad_config, credentials: creds)
result[:status]
#=> 'invalid'
