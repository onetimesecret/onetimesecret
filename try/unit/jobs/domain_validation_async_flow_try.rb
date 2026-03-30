# try/unit/jobs/domain_validation_async_flow_try.rb
#
# frozen_string_literal: true

# Tests for async DNS validation flow introduced in #2834
#
# Validates:
# 1. ValidateSenderDomain Result error field is a String (not an Exception)
# 2. Raising result.error produces a RuntimeError (enabling with_retry)
# 3. BaseWorker with_retry retries on transient errors and respects max_retries
# 4. Publisher sync fallback updates verification_status from pending
# 5. Status rollback concept when publishing fails
# 6. End-to-end async flow: pending -> enqueue -> worker validates -> status transitions

require_relative '../../support/test_helpers'
require 'securerandom'
require 'resolv'

OT.boot! :test

require 'onetime/jobs/queues/config'
require 'onetime/jobs/queues/declarator'
require 'onetime/jobs/publisher'
require 'onetime/jobs/workers/base_worker'
require 'onetime/operations/validate_sender_domain'
require 'onetime/models/custom_domain/mailer_config'

@timestamp = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "async_owner_#{@timestamp}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("Async Test Org #{@timestamp}", @owner, "async_#{@timestamp}@test.com")
@domain = Onetime::CustomDomain.create!("async-test-#{@timestamp}.example.com", @org.objid)

@config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier,
  provider: 'ses',
  from_name: 'Async Test Sender',
  from_address: "noreply@async-test-#{@timestamp}.example.com",
)

@error_result = Onetime::Operations::ValidateSenderDomain::Result.new(
  domain: 'test.example.com',
  provider: 'ses',
  dns_records: [],
  all_verified: false,
  verification_status: 'failed',
  verified_at: nil,
  persisted: false,
  error: 'DNS resolution timed out',
)

@ok_result = Onetime::Operations::ValidateSenderDomain::Result.new(
  domain: 'test.example.com',
  provider: 'ses',
  dns_records: [{ type: 'CNAME', verified: true }],
  all_verified: true,
  verification_status: 'verified',
  verified_at: Time.now,
  persisted: true,
  error: nil,
)

@retry_helper = Class.new do
  include Onetime::Jobs::Workers::BaseWorker::InstanceMethods
  def self.worker_name; 'RetryTestWorker'; end
end.new

# --- Result.error type and raise behavior ---

## ValidateSenderDomain Result error field stores a String (ex.message), not an Exception
@error_result.error.class
#=> String

## Raising a String error produces a RuntimeError
# The worker does `raise result.error if result.error` where result.error
# is a String. Ruby's `raise "some string"` creates a RuntimeError.
begin
  raise @error_result.error
rescue => ex
  @raise_class = ex.class
end
@raise_class
#=> RuntimeError

## RuntimeError is a StandardError (so with_retry catches it)
RuntimeError < StandardError
#=> true

## Result with nil error reports success
@ok_result.success?
#=> true

## Result with error string reports not success
@error_result.success?
#=> false

# --- BaseWorker with_retry behavior ---

## with_retry retries the expected number of times before raising
# Track how many times the block is called. max_retries: 2 means
# 1 initial attempt + 2 retries = 3 total calls.
@call_count = 0
begin
  @retry_helper.with_retry(max_retries: 2, base_delay: 0.01) do
    @call_count += 1
    raise 'transient DNS failure'
  end
rescue RuntimeError
  # expected
end
@call_count
#=> 3

## with_retry does not retry when block succeeds
@success_count = 0
@retry_helper.with_retry(max_retries: 2, base_delay: 0.01) do
  @success_count += 1
  'ok'
end
@success_count
#=> 1

## with_retry re-raises original error class after exhausting retries
begin
  @retry_helper.with_retry(max_retries: 1, base_delay: 0.01) do
    raise Resolv::ResolvError, 'DNS resolution failed'
  end
rescue => ex
  @raised_class = ex.class
end
@raised_class
#=> Resolv::ResolvError

## with_retry retries then succeeds if block eventually passes
@attempt = 0
@recovered = @retry_helper.with_retry(max_retries: 3, base_delay: 0.01) do
  @attempt += 1
  raise 'transient' if @attempt < 3
  'recovered'
end
@recovered
#=> "recovered"

## with_retry skips retries for non-retriable errors
@non_retriable_count = 0
@retriable_check = ->(ex) { !ex.message.include?('permanent') }
begin
  @retry_helper.with_retry(max_retries: 3, base_delay: 0.01, retriable: @retriable_check) do
    @non_retriable_count += 1
    raise 'permanent failure'
  end
rescue RuntimeError
  # expected
end
@non_retriable_count
#=> 1

# --- Retry interaction with ValidateSenderDomain Result ---

## with_retry retries when ValidateSenderDomain returns error Result
# This simulates the actual worker code pattern: call the operation,
# then raise result.error if present, triggering with_retry.
@op_call_count = 0
begin
  @retry_helper.with_retry(max_retries: 1, base_delay: 0.01) do
    @op_call_count += 1
    @inner_result = Onetime::Operations::ValidateSenderDomain::Result.new(
      domain: 'flaky.example.com',
      provider: 'ses',
      dns_records: [],
      all_verified: false,
      verification_status: 'failed',
      verified_at: nil,
      persisted: false,
      error: 'DNS resolution timed out',
    )
    raise @inner_result.error if @inner_result.error
  end
rescue RuntimeError
  # expected after retries exhausted
end
@op_call_count
#=> 2

## with_retry does NOT retry when Result has no error
@no_error_count = 0
@retry_helper.with_retry(max_retries: 2, base_delay: 0.01) do
  @no_error_count += 1
  Onetime::Operations::ValidateSenderDomain::Result.new(
    domain: 'good.example.com',
    provider: 'ses',
    dns_records: [{ type: 'CNAME', verified: true }],
    all_verified: true,
    verification_status: 'verified',
    verified_at: Time.now,
    persisted: true,
    error: nil,
  )
end
@no_error_count
#=> 1

# --- Status rollback on publish failure ---

## MailerConfig verification_status starts as pending (from create!)
@config_fresh = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@config_fresh.verification_status
#=> "pending"

## Status can be set to verified and persisted with partial save
@config_fresh.verification_status = 'verified'
@config_fresh.updated = Familia.now.to_i
@config_fresh.save_fields(:verification_status, :updated)
@reloaded = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@reloaded.verification_status
#=> "verified"

## Rollback pattern restores previous status when publish fails
# This tests the pattern from validate_sender_config.rb:
#   1. Save previous_status
#   2. Set to 'pending'
#   3. If publish fails, restore previous_status
@prev_status = @reloaded.verification_status
@reloaded.verification_status = 'pending'
@reloaded.updated = Familia.now.to_i
@reloaded.save_fields(:verification_status, :updated)
begin
  raise Onetime::Problem, 'RabbitMQ channel pool not initialized'
rescue => _ex
  @reloaded.verification_status = @prev_status
  @reloaded.updated = Familia.now.to_i
  @reloaded.save_fields(:verification_status, :updated)
end
@rolled_back = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@rolled_back.verification_status
#=> "verified"

## Without rollback, status stays stuck in pending (demonstrates the bug Fix 2 prevents)
@rolled_back.verification_status = 'pending'
@rolled_back.updated = Familia.now.to_i
@rolled_back.save_fields(:verification_status, :updated)
begin
  raise Onetime::Problem, 'RabbitMQ channel pool not initialized'
rescue => _ex
  # no rollback
end
@stuck = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@stuck.verification_status
#=> "pending"

# --- Sync fallback end-to-end status transition ---

## Sync fallback transitions MailerConfig from pending to verified or failed
# When jobs are disabled ($rmq_channel_pool is nil), Publisher falls back
# to synchronous validation. The operation updates verification_status.
@stuck.verification_status = 'pending'
@stuck.updated = Familia.now.to_i
@stuck.save_fields(:verification_status, :updated)
Onetime::Jobs::Publisher.enqueue_domain_validation(@domain.identifier)
@after_sync = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
%w[verified failed].include?(@after_sync.verification_status)
#=> true

## Sync fallback returns true (consistent with async path)
Onetime::Jobs::Publisher.enqueue_domain_validation(@domain.identifier)
#=> true

# --- Idempotency claim behavior ---

## claim_for_processing succeeds on first call for a new message_id
@idempotency_helper = Class.new do
  include Onetime::Jobs::Workers::BaseWorker::InstanceMethods
  def self.worker_name; 'IdempotencyTestWorker'; end
end.new
@test_msg_id = "test-idem-#{SecureRandom.uuid}"
@idempotency_helper.claim_for_processing(@test_msg_id)
#=> true

## claim_for_processing returns false on second call (duplicate)
@idempotency_helper.claim_for_processing(@test_msg_id)
#=> false

## claim_for_processing returns false for nil message_id
@idempotency_helper.claim_for_processing(nil)
#=> false

# Teardown
Familia.dbclient.flushdb
