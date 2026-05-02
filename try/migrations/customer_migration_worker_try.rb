# try/migrations/customer_migration_worker_try.rb
#
# frozen_string_literal: true

# Skeleton tests for CustomerMigrationWorker public interface.
#
# Most test bodies are pending: implementation — this file validates that
# the class loads, constants are defined, and error taxonomy is correct.
# Uncomment and flesh out as the worker is implemented.
#
# Does NOT require RabbitMQ or Redis — tests use stubs where needed.
#
# Run:
#   try --agent try/migrations/customer_migration_worker_try.rb

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/workers/customer_migration_worker'

@worker_class = Onetime::Jobs::Workers::CustomerMigrationWorker

# TRYOUTS

## Worker class exists
@worker_class.is_a?(Class)
#=> true

## Worker includes Sneakers::Worker
@worker_class.ancestors.include?(Sneakers::Worker)
#=> true

## Worker includes BaseWorker
@worker_class.ancestors.include?(Onetime::Jobs::Workers::BaseWorker)
#=> true

## QUEUE_NAME is set to migration.customer.batch
@worker_class::QUEUE_NAME
#=> 'migration.customer.batch'

## HardInfrastructureError is a StandardError
@worker_class::HardInfrastructureError.ancestors.include?(StandardError)
#=> true

## RecordTransformError is a StandardError
@worker_class::RecordTransformError.ancestors.include?(StandardError)
#=> true

## IdentifierDerivationError is a RecordTransformError
@worker_class::IdentifierDerivationError.ancestors.include?(
  @worker_class::RecordTransformError
)
#=> true

## RecordWriteError is a RecordTransformError
@worker_class::RecordWriteError.ancestors.include?(
  @worker_class::RecordTransformError
)
#=> true

## RecordTransformError carries custid
begin
  raise @worker_class::RecordTransformError.new('boom', custid: 'user@example.com')
rescue @worker_class::RecordTransformError => ex
  ex.custid
end
#=> 'user@example.com'

## HARD_ERROR_PATTERNS covers WRONGTYPE
@worker_class::HARD_ERROR_PATTERNS.any? { |p| p.match?('WRONGTYPE Operation against a key') }
#=> true

## HARD_ERROR_PATTERNS covers NOAUTH
@worker_class::HARD_ERROR_PATTERNS.any? { |p| p.match?('NOAUTH Authentication required') }
#=> true

## HARD_ERROR_PATTERNS covers DUMP payload
@worker_class::HARD_ERROR_PATTERNS.any? { |p| p.match?('DUMP payload version or checksum are wrong') }
#=> true

## HARD_ERROR_PATTERNS does NOT match a plain connection error
@worker_class::HARD_ERROR_PATTERNS.any? { |p| p.match?('Connection refused - connect(2)') }
#=> false

# ── Pending: requires implementation ────────────────────────────────────────

# The tests below document expected behavior. Uncomment and implement when
# the corresponding worker method is complete.

## [pending] already_migrated_and_current? returns false for unknown custid
# worker = @worker_class.new
# worker.send(:already_migrated_and_current?, 'user@example.com', {})
#=> false

## [pending] redact strips local-part from email custid
# worker = @worker_class.new
# worker.send(:redact, 'alice@example.com')
#=> '@example.com'

## [pending] redact handles nil
# worker = @worker_class.new
# worker.send(:redact, nil)
#=> '[nil]'

## [pending] pipeline_enabled? is false when env var is unset
# ENV.delete('OTS_MIGRATION_PIPELINE')
# worker = @worker_class.new
# worker.send(:pipeline_enabled?)
#=> false

## [pending] pipeline_enabled? is true when env var is '1'
# ENV['OTS_MIGRATION_PIPELINE'] = '1'
# worker = @worker_class.new
# worker.send(:pipeline_enabled?)
#=> true

## [pending] hard_redis_error? returns true for WRONGTYPE message
# worker = @worker_class.new
# ex = Redis::CommandError.new('WRONGTYPE Operation against a key holding the wrong kind of value')
# worker.send(:hard_redis_error?, ex)
#=> true

## [pending] hard_redis_error? returns false for ordinary connection error
# worker = @worker_class.new
# ex = Redis::CannotConnectError.new('Connection refused')
# worker.send(:hard_redis_error?, ex)
#=> false
