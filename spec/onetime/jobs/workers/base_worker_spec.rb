# spec/onetime/jobs/workers/base_worker_spec.rb
# frozen_string_literal: true

# Tests for Onetime::Jobs::Workers::BaseWorker
#
# Purpose:
#   Verifies the shared worker functionality provided by BaseWorker module,
#   including message parsing, idempotency checks, retry logic, and metadata
#   extraction.
#
# Test Categories:
#   - Property extraction (Unit):
#       * message_id: Extracts message_id from delivery_info properties
#
#   - Idempotency (Integration - requires Redis):
#       * already_processed? returns true when key exists
#       * already_processed? returns false when key absent
#       * mark_processed sets Redis key with SETEX and correct TTL
#
#   - Message parsing (Unit):
#       * parse_message returns hash from valid JSON
#       * parse_message rejects invalid JSON (mocked reject!)
#
#   - Retry logic (Unit):
#       * with_retry retries on failure then succeeds
#       * with_retry exhausts max retries then rejects (mocked reject!)
#
# Setup Requirements:
#   - Redis test instance: VALKEY_URL='valkey://127.0.0.1:2121/0'
#   - Mocked delivery_info struct (Sneakers/Kicks format)
#   - Mocked ack!/reject! methods on test worker instance
#
# Trust Rationale:
#   - Unit tests: Mock external dependencies, verify isolated logic
#   - Integration tests: Use real Redis to verify I/O and TTL behavior
#
