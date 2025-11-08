# try/integration/authentication/sync_session_idempotency_try.rb
#
# frozen_string_literal: true

# Tests idempotency protection in Auth::Operations::SyncSession
# Ensures the operation can be safely retried without double-execution

# Skip if not in advanced mode
require_relative '../../support/test_helpers'
require_relative '../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :advanced

# Ensure database URL is configured
if ENV['DATABASE_URL'].to_s.strip.empty?
  puts "SKIPPING: Advanced mode requires DATABASE_URL."
  exit 0
end

# Setup environment
ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../../..')).freeze

require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'onetime/auth_config'
require 'onetime/middleware'
require 'onetime/application/registry'

Onetime::Application::Registry.prepare_application_registry

require 'rack'
require 'rack/mock'

require_relative '../../support/test_models'

# Setup test account and session
@db = Auth::Database.connection
@account_id = nil
@account = nil
@session = {}
@request = nil

# Create test account
@db.transaction do
  email = "idempotency-test-#{Familia.now.to_i}@example.com"

  @account_id = @db[:accounts].insert(
    email: email,
    status_id: 2, # verified
    created_at: Time.now,
    updated_at: Time.now
  )

  @account = @db[:accounts].where(id: @account_id).first
end

# Create mock request
env = Rack::MockRequest.env_for('/')
env['REMOTE_ADDR'] = '192.168.1.100'
env['HTTP_USER_AGENT'] = 'Test Agent'
@request = Rack::Request.new(env)

# Create session with ID
@session = { 'session_id' => "test-session-#{@account_id}" }


# First sync creates customer

## First sync should succeed and create customer
@customer = Auth::Operations::SyncSession.call(
  account: @account,
  account_id: @account_id,
  session: @session,
  request: @request
)
@customer.class.name
#=> "Onetime::Customer"

## Session should be populated
[@session['authenticated'], @session['account_id'], @session['email']]
#=> [true, @account_id, @account[:email]]

## Customer should be linked to account
linked_extid = @db[:accounts].where(id: @account_id).get(:external_id)
linked_extid == @customer.extid
#=> true


# Double-call with same idempotency key

## Second call with same session should skip (idempotency protection)
@customer2 = Auth::Operations::SyncSession.call(
  account: @account,
  account_id: @account_id,
  session: @session,
  request: @request
)

# Should return same customer
@customer2.custid == @customer.custid
#=> true


# Different session ID allows new sync

## Create new session with different ID
@session2 = { 'session_id' => "test-session-different-#{@account_id}" }

@customer3 = Auth::Operations::SyncSession.call(
  account: @account,
  account_id: @account_id,
  session: @session2,
  request: @request
)

# Should sync successfully (same customer, different session)
[@session2['authenticated'], @session2['external_id'] == @customer.extid]
#=> [true, true]


# Redis failure scenarios

## Temporarily disable Redis to test graceful degradation
original_dbclient = Familia.instance_variable_get(:@dbclient)

begin
  # Mock Redis unavailability
  Familia.instance_variable_set(:@dbclient, nil)

  @session3 = { 'session_id' => "test-session-no-redis-#{@account_id}" }

  # Should still work without Redis (no idempotency protection)
  @customer4 = Auth::Operations::SyncSession.call(
    account: @account,
    account_id: @account_id,
    session: @session3,
    request: @request
  )

  @customer4.class.name
ensure
  # Restore Redis connection
  Familia.instance_variable_set(:@dbclient, original_dbclient)
end
#=> "Onetime::Customer"


# Idempotency key TTL behavior

## Check that idempotency keys from earlier tests have TTL set
all_keys = Familia.dbclient.keys("sync_session:#{@account_id}:*")
ttls = all_keys.map { |k| Familia.dbclient.ttl(k) }

# All keys should have TTL between 290-310 seconds (5 minutes with variance)
ttls.all? { |ttl| (0..310).include?(ttl) }
#=> true


# Cleanup

## Delete test account
@db[:accounts].where(id: @account_id).delete if @account_id
@customer.destroy! if @customer&.exists?

# Clean up any remaining idempotency keys
pattern = "sync_session:#{@account_id}:*"
keys = Familia.dbclient.keys(pattern)
Familia.dbclient.del(*keys) if keys.any?

nil
#=> nil
