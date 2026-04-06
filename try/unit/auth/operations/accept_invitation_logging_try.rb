# try/unit/auth/operations/accept_invitation_logging_try.rb
#
# frozen_string_literal: true

# Tests for AcceptInvitation operation structured logging.
#
# Verifies that Auth::Logging.log_operation is called with the expected
# fields including organization_id, email (for obscuring), role, etc.
#
# Run: bundle exec try try/unit/auth/operations/accept_invitation_logging_try.rb

require_relative '../../../support/test_helpers'
require 'stringio'

OT.boot! :test

# Auth::Logging is required by accept_invitation but not auto-loaded
require 'web/auth/lib/logging'
require 'web/auth/operations/accept_invitation'

# Setup: Create owner and organization
@owner_email = generate_unique_test_email('log_owner')
@owner = Onetime::Customer.create!(email: @owner_email)
@org = Onetime::Organization.create!('Logging Test Org', @owner, @owner_email, is_default: true)

# Setup: Create invitee customer (simulating new account)
@invitee_email = generate_unique_test_email('log_invitee')
@invitee = Onetime::Customer.create!(email: @invitee_email)

# Setup: Create invitation for the invitee
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee_email,
  role: 'admin',
  inviter: @owner
)
@valid_token = @invitation.token

# Create a capture array at module level
CAPTURED_LOGS = []

# Store original method
@original_log_operation = Auth::Logging.singleton_class.instance_method(:log_operation)

# Define replacement method that captures logs
Auth::Logging.define_singleton_method(:log_operation) do |operation, **payload|
  CAPTURED_LOGS << { operation: operation, payload: payload }
  # Call through to logger to keep pipeline intact
  logger = Onetime.get_logger('Auth')
  log_payload = payload.dup
  log_payload[:email] = OT::Utils.obscure_email(log_payload[:email]) if log_payload[:email]
  log_payload[:correlation_id] ||= 'none'
  level = payload[:level] || :info
  logger.public_send(level, "[#{operation}]", log_payload)
end

# TRYOUTS

## Auth::Logging module responds to log_operation
Auth::Logging.respond_to?(:log_operation)
#=> true

## Auth::Logging module responds to log_error
Auth::Logging.respond_to?(:log_error)
#=> true

## AcceptInvitation succeeds with valid token
CAPTURED_LOGS.clear
@result = Auth::Operations::AcceptInvitation.new(
  customer: @invitee,
  token: @valid_token
).call
@result[:accepted]
#=> true

## Log captures invitation_accepted operation
@accepted_log = CAPTURED_LOGS.find { |l| l[:operation] == :invitation_accepted }
@accepted_log.nil? == false
#=> true

## Log payload includes customer_id field
@accepted_log[:payload].key?(:customer_id)
#=> true

## Log payload includes email field (for automatic obscuring)
@accepted_log[:payload].key?(:email)
#=> true

## Log payload email matches invitee email
@accepted_log[:payload][:email] == @invitee_email
#=> true

## Log payload includes organization_id field
@accepted_log[:payload].key?(:organization_id)
#=> true

## Log payload organization_id matches org objid
@accepted_log[:payload][:organization_id] == @org.objid
#=> true

## Log payload includes organization_name field
@accepted_log[:payload].key?(:organization_name)
#=> true

## Log payload includes role field
@accepted_log[:payload][:role]
#=> 'admin'

## Log payload includes invite_token_prefix field
@accepted_log[:payload].key?(:invite_token_prefix)
#=> true

## Log payload invite_token_prefix is first 8 chars of token
@accepted_log[:payload][:invite_token_prefix] == @valid_token[0..7]
#=> true

## Log payload includes verified_by field
@accepted_log[:payload][:verified_by]
#=> 'invite_token'

## Log payload includes level: :info
@accepted_log[:payload][:level]
#=> :info

# Test skipped invitation logging

## Setup fresh invitation for skip test
@skip_invitee_email = generate_unique_test_email('log_skip')
@skip_invitee = Onetime::Customer.create!(email: @skip_invitee_email)
@skip_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: generate_unique_test_email('mismatch_target'),
  role: 'member',
  inviter: @owner
)
true
#=> true

## AcceptInvitation with email mismatch returns email_mismatch reason
CAPTURED_LOGS.clear
@mismatch_result = Auth::Operations::AcceptInvitation.new(
  customer: @skip_invitee,
  token: @skip_invitation.token
).call
@mismatch_result[:reason]
#=> 'email_mismatch'

## Skipped log is captured with invitation_skipped operation
@skipped_log = CAPTURED_LOGS.find { |l| l[:operation] == :invitation_skipped }
@skipped_log.nil? == false
#=> true

## Skipped log includes reason field
@skipped_log[:payload][:reason]
#=> 'email_mismatch'

## AcceptInvitation logs invitation_skipped with no_token reason
CAPTURED_LOGS.clear
@no_token_result = Auth::Operations::AcceptInvitation.new(
  customer: @skip_invitee,
  token: nil
).call
@no_token_log = CAPTURED_LOGS.find { |l| l[:operation] == :invitation_skipped }
@no_token_log[:payload][:reason]
#=> 'no_token'

# Cleanup
[@owner, @invitee, @skip_invitee].each { |c| c&.destroy! rescue nil }
[@invitation, @skip_invitation].each { |i| i&.destroy_with_index_cleanup! rescue nil }
@org&.destroy! rescue nil
