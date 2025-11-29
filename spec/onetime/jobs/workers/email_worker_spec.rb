# spec/onetime/jobs/workers/email_worker_spec.rb
#
# frozen_string_literal: true

# EmailWorker Test Suite
#
# Tests the email delivery worker that consumes messages from the
# email.immediate queue and delivers emails via Onetime::Mail.
#
# Test Categories:
#
#   1. Templated email delivery (Unit)
#      - Verifies Mail.deliver is called with correct template and data
#      - Uses mocked Mail module to verify method arguments
#
#   2. Raw email delivery (Unit)
#      - Verifies Mail.deliver_raw is called with correct email hash
#      - Uses mocked Mail module to verify method arguments
#
#   3. Idempotency skip (Integration)
#      - Tests that pre-existing Redis key prevents duplicate delivery
#      - Uses real Redis instance with mocked Mail module
#
#   4. Idempotency mark (Integration)
#      - Tests that successful delivery creates Redis idempotency key
#      - Uses real Redis instance with mocked Mail module
#
#   5. Failure handling (Unit)
#      - Tests that Mail errors trigger reject! to send to DLQ
#      - Uses mocked Mail and Sneakers methods (ack!/reject!)
#
# Setup Requirements:
#   - Redis test instance at VALKEY_URL='valkey://127.0.0.1:2121/0'
#   - Mocked Onetime::Mail module (Mail.deliver, Mail.deliver_raw)
#   - Mocked Sneakers methods (ack!, reject!, delivery_info)
#   - Redis idempotency key cleanup between tests
#
# Run with: bundle exec rspec spec/onetime/jobs/workers/email_worker_spec.rb

require 'spec_helper'
