# apps/web/auth/try/operations/close_account_try.rb
#
# frozen_string_literal: true

# CloseAccount Operation Test Suite
#
# Tests the deletion of auth accounts and all related data from the auth
# database. This operation is used when a user deletes their account.

# Setup - Load the real application with full auth mode
ENV['RACK_ENV']            = 'test'
ENV['AUTHENTICATION_MODE'] = 'full'

require_relative '../../../../../try/support/test_helpers'

require 'onetime'

OT.boot! :test, false

require_relative '../../operations/close_account'

@db = Auth::Database.connection

# Create a test account directly in the auth database
@test_email = generate_unique_test_email("closeaccount")
@test_extid = "test_extid_#{SecureRandom.hex(8)}"

@db.transaction do
  @account_id = @db[:accounts].insert(
    email: @test_email,
    status_id: 2,
    external_id: @test_extid,
    created_at: Time.now,
    updated_at: Time.now
  )

  # Insert related records to verify cascade deletion
  @db[:account_password_hashes].insert(
    id: @account_id,
    password_hash: '$argon2id$v=19$m=16384,t=2,p=1$fakehash',
    created_at: Time.now
  )

  @db[:account_remember_keys].insert(
    id: @account_id,
    key: SecureRandom.hex(32),
    deadline: Time.now + 86400
  )
end

## CloseAccount requires extid parameter
result = Auth::Operations::CloseAccount.new(extid: nil).call
result[:success]
#=> false

## CloseAccount returns error for missing extid
result = Auth::Operations::CloseAccount.new(extid: '').call
result[:error]
#=> 'External ID is required'

## CloseAccount returns error for non-existent account
result = Auth::Operations::CloseAccount.new(extid: 'nonexistent_extid').call
result[:success]
#=> false

## CloseAccount returns error message for non-existent account
result = Auth::Operations::CloseAccount.new(extid: 'nonexistent_extid').call
result[:error].include?('No auth account found')
#=> true

## CloseAccount successfully deletes account by extid
@delete_result = Auth::Operations::CloseAccount.new(extid: @test_extid).call
@delete_result[:success]
#=> true

## CloseAccount returns account_id on success
@delete_result[:account_id]
#=> @account_id

## Account is deleted from accounts table
@db[:accounts].where(external_id: @test_extid).count
#=> 0

## Password hash is deleted from account_password_hashes table
@db[:account_password_hashes].where(id: @account_id).count
#=> 0

## Remember key is deleted from account_remember_keys table
@db[:account_remember_keys].where(id: @account_id).count
#=> 0

## CloseAccount class method works as convenience
result = Auth::Operations::CloseAccount.call(extid: 'another_nonexistent')
result[:success]
#=> false

# Teardown
begin
  # Clean up any remaining test data (should be none if test passed)
  @db[:account_remember_keys].where(id: @account_id).delete
  @db[:account_password_hashes].where(id: @account_id).delete
  @db[:accounts].where(id: @account_id).delete
rescue StandardError => ex
  # Ignore cleanup errors - data should already be deleted
end
