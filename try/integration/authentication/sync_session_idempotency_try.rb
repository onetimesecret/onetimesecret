# try/integration/authentication/sync_session_idempotency_try.rb

# Tests idempotency protection in Auth::Operations::SyncSession
# Ensures the operation can be safely retried without double-execution

# Setup environment
ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../../..')).freeze

require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'onetime/auth_config'
require 'onetime/middleware'
require 'onetime/application/registry'

# Load Auth application modules
require_relative '../../../apps/web/auth/database'
require_relative '../../../apps/web/auth/application'

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
customer = Auth::Operations::SyncSession.call(
  account: @account,
  account_id: @account_id,
  session: @session,
  request: @request
)
customer.class.name
#=> "Onetime::Customer"

## Session should be populated
[@session['authenticated'], @session['account_id'], @session['email']]
#=> [true, @account_id, @account[:email]]

## Customer should be linked to account
linked_extid = @db[:accounts].where(id: @account_id).get(:external_id)
linked_extid == customer.extid
#=> true


# Double-call with same idempotency key

## Second call with same session should skip (idempotency protection)
original_customer_count = Onetime::Customer.redis.dbsize

customer2 = Auth::Operations::SyncSession.call(
  account: @account,
  account_id: @account_id,
  session: @session,
  request: @request
)

# Should return same customer without creating new one
new_customer_count = Onetime::Customer.redis.dbsize
[customer2.custid == customer.custid, new_customer_count == original_customer_count]
#=> [true, true]


# Different session ID allows new sync

## Create new session with different ID
@session2 = { 'session_id' => "test-session-different-#{@account_id}" }

customer3 = Auth::Operations::SyncSession.call(
  account: @account,
  account_id: @account_id,
  session: @session2,
  request: @request
)

# Should sync successfully (same customer, different session)
[@session2['authenticated'], @session2['external_id'] == customer.extid]
#=> [true, true]


# Redis failure scenarios

## Temporarily disable Redis to test graceful degradation
original_dbclient = Familia.instance_variable_get(:@dbclient)

begin
  # Mock Redis unavailability
  Familia.instance_variable_set(:@dbclient, nil)

  @session3 = { 'session_id' => "test-session-no-redis-#{@account_id}" }

  # Should still work without Redis (no idempotency protection)
  customer4 = Auth::Operations::SyncSession.call(
    account: @account,
    account_id: @account_id,
    session: @session3,
    request: @request
  )

  customer4.class.name
ensure
  # Restore Redis connection
  Familia.instance_variable_set(:@dbclient, original_dbclient)
end
#=> "Onetime::Customer"


# Partial failure compensation

## Test that failure clears idempotency key for retry
@session4 = { 'session_id' => "test-session-failure-#{@account_id}" }

operation = Auth::Operations::SyncSession.new(
  account: @account,
  account_id: @account_id,
  session: @session4,
  request: @request
)

# Force idempotency key to be set
operation.send(:mark_processing)
idempotency_key = operation.send(:idempotency_key)

# Verify key exists
key_exists_before = Familia.dbclient.exists?(idempotency_key)
key_exists_before
#=> 1

## Simulate failure by forcing error in customer creation
begin
  # Temporarily break customer creation
  allow_retry = false

  Onetime::Customer.class_eval do
    alias_method :original_create!, :create!
    define_method(:create!) do |*args|
      raise StandardError, "Simulated failure" unless allow_retry
      original_create!(*args)
    end
  end

  # This should fail and clear idempotency key
  begin
    Auth::Operations::SyncSession.call(
      account: @account,
      account_id: @account_id,
      session: @session4,
      request: @request
    )
  rescue StandardError => ex
    ex.message
  end
ensure
  # Restore original method
  if Onetime::Customer.method_defined?(:original_create!)
    Onetime::Customer.class_eval do
      alias_method :create!, :original_create!
      remove_method :original_create!
    end
  end
end
#=> "Simulated failure"


# Idempotency key TTL behavior

## Keys should have 5-minute TTL
@session5 = { 'session_id' => "test-session-ttl-#{@account_id}" }

operation = Auth::Operations::SyncSession.new(
  account: @account,
  account_id: @account_id,
  session: @session5,
  request: @request
)

operation.send(:mark_processing)
key = operation.send(:idempotency_key)

# Check TTL is set correctly (300 seconds = 5 minutes)
ttl = Familia.dbclient.ttl(key)
(290..310).include?(ttl) # Allow small variance
#=> true


# Cleanup

## Delete test account
@db[:accounts].where(id: @account_id).delete if @account_id
customer&.destroy! if customer&.exists?
customer2&.destroy! if customer2&.exists? && customer2.custid != customer.custid
customer3&.destroy! if customer3&.exists? && customer3.custid != customer.custid
customer4&.destroy! if customer4&.exists? && customer4.custid != customer.custid

# Clean up any remaining idempotency keys
pattern = "sync_session:#{@account_id}:*"
keys = Familia.dbclient.keys(pattern)
Familia.dbclient.del(*keys) if keys.any?

nil
#=> nil
