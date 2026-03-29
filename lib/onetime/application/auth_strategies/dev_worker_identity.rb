# lib/onetime/application/auth_strategies/dev_worker_identity.rb
#
# frozen_string_literal: true

#
# Provides collision-resistant username generation for parallel CI execution.
#
# When multiple CI workers run in parallel (e.g., different auth modes testing
# against the same Redis instance), using a fixed username like `dev_alice`
# would cause Redis key collisions. This module generates namespaced usernames
# that are:
#
# - **Predictable**: Same input and worker context always produces the same output
# - **Collision-resistant**: Different workers get different namespaces
# - **Transparent**: Tests don't need to change how they call auth
#
# ## Environment Variables (checked in order)
#
# 1. `DEV_WORKER_ID` - Explicit worker identifier (most predictable)
# 2. `GITHUB_JOB` - GitHub Actions job name (e.g., "ruby-integration-simple")
# 3. `TEST_ENV_NUMBER` - Parallel test gem worker number
# 4. `CIRCLE_NODE_INDEX` - CircleCI parallelism index
#
# If none are set, falls back to a process-unique identifier (PID + timestamp).
#
# ## Examples
#
#   # With DEV_WORKER_ID=simple
#   DevWorkerIdentity.namespaced_username("alice")
#   #=> "alice_w2dc1"  (hash of "simple")
#
#   # With GITHUB_JOB=ruby-integration-full-postgres
#   DevWorkerIdentity.namespaced_username("alice")
#   #=> "alice_wf8b3"  (hash of job name)
#
#   # Without any env vars (falls back to process-unique)
#   DevWorkerIdentity.namespaced_username("alice")
#   #=> "alice_w1234_1711234567"  (PID + timestamp)
#
# ## Integration
#
# Used by DevBasicAuthStrategy and DevSessionAuthStrategy to transform
# the raw dev_ username into a collision-resistant variant before creating
# or looking up the Customer record.
#
# @see DevBasicAuthStrategy#find_or_create_dev_customer
# @see https://github.com/onetimesecret/onetimesecret/issues/2735
#
module Onetime
  module Application
    module AuthStrategies
      module DevWorkerIdentity
        # Short hash length for worker namespace suffix
        NAMESPACE_LENGTH = 4

        class << self
          # Transform a dev username to be collision-resistant across workers.
          #
          # The namespace suffix is appended to ensure different workers get
          # different Redis keys for the same logical username.
          #
          # @param raw_username [String] The original username (e.g., "alice")
          # @return [String] Namespaced username (e.g., "alice_w2dc1")
          #
          # @example Basic usage
          #   namespaced_username("alice") #=> "alice_w2dc1"
          #
          # @example With dev_ prefix (prefix is preserved)
          #   # Called with "dev_alice" after stripping prefix:
          #   namespaced_username("alice") #=> "alice_w2dc1"
          #
          def namespaced_username(raw_username)
            suffix = worker_namespace_suffix
            "#{raw_username}_#{suffix}"
          end

          # Compute a short, deterministic worker namespace suffix.
          #
          # Uses environment variables when available for reproducibility,
          # falling back to process-unique identifiers otherwise.
          #
          # @return [String] A namespace suffix like "w2dc1" or "w1234_1711234567"
          def worker_namespace_suffix
            worker_id = detect_worker_id
            if worker_id
              hash_suffix(worker_id)
            else
              process_unique_suffix
            end
          end

          # Detect worker ID from environment variables.
          #
          # Checks multiple CI/test environment variables in priority order.
          #
          # @return [String, nil] The worker identifier or nil if none found
          def detect_worker_id
            # Priority order: explicit > CI-specific > test parallelism
            ENV['DEV_WORKER_ID'] ||
              ENV['GITHUB_JOB'] ||
              ENV['TEST_ENV_NUMBER'] ||
              ENV.fetch('CIRCLE_NODE_INDEX', nil)
          end

          # Check if running in a CI environment with parallelism.
          #
          # @return [Boolean] true if a worker ID was detected
          def parallel_ci?
            !detect_worker_id.nil?
          end

          # Get the raw worker ID for logging/debugging.
          #
          # @return [String] The worker ID or "local" if not in CI
          def worker_id_for_logging
            detect_worker_id || 'local'
          end

          private

          # Hash a worker ID to a short suffix.
          #
          # @param worker_id [String] The raw worker identifier
          # @return [String] A suffix like "w2dc1" (w + 4 hex chars)
          def hash_suffix(worker_id)
            # Use MD5 for speed - this is not security-sensitive
            hash = Digest::MD5.hexdigest(worker_id.to_s)
            "w#{hash[0, NAMESPACE_LENGTH]}"
          end

          # Generate a process-unique suffix for non-CI environments.
          #
          # Uses PID and timestamp to ensure uniqueness within a single
          # machine, but note this is not reproducible across runs.
          #
          # @return [String] A suffix like "w1234_1711234567"
          def process_unique_suffix
            # Cache per-process to maintain consistency within a test run
            @process_unique_suffix ||= "w#{Process.pid}_#{Time.now.to_i}"
          end
        end
      end
    end
  end
end
