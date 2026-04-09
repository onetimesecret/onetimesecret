# lib/onetime/jobs/workers/job_lifecycle.rb
#
# frozen_string_literal: true

module Onetime
  module Jobs
    module Workers
      # Standard job lifecycle status constants for background workers.
      #
      # These statuses track WHERE a job is in its execution lifecycle,
      # deliberately separate from the OUTCOME of the work performed.
      #
      # Separation of Concerns:
      #   - Lifecycle status answers: "Has the worker finished?"
      #   - Outcome fields answer: "Did the check pass?"
      #
      # Example usage in MailerConfig:
      #   - dns_check_status: QUEUED -> PROCESSING -> COMPLETED (lifecycle)
      #   - dns_verified: nil -> true/false (outcome)
      #
      # The lifecycle status tells the frontend whether to keep polling.
      # The outcome tells the user what happened.
      #
      # Note: FAILED here means the worker crashed or encountered an
      # unrecoverable error (e.g., message sent to DLQ). A successful
      # verification that determined "DNS records don't match" would
      # still be status=COMPLETED with verified=false.
      #
      module JobLifecycle
        # Message published to queue, not yet picked up by a worker
        QUEUED = 'queued'

        # Worker has claimed the message and is actively processing
        PROCESSING = 'processing'

        # Worker finished execution (check outcome fields for result)
        COMPLETED = 'completed'

        # Worker crashed or encountered unrecoverable error (message sent to DLQ)
        FAILED = 'failed'

        ALL_STATUSES = [QUEUED, PROCESSING, COMPLETED, FAILED].freeze

        # Check if a status value represents a terminal state (no more updates expected)
        #
        # @param status [String, nil] The status to check
        # @return [Boolean] true if status is COMPLETED or FAILED
        def self.terminal?(status)
          [COMPLETED, FAILED].include?(status)
        end

        # Check if a status value represents an active state (worker is working on it)
        #
        # @param status [String, nil] The status to check
        # @return [Boolean] true if status is QUEUED or PROCESSING
        def self.active?(status)
          [QUEUED, PROCESSING].include?(status)
        end
      end
    end
  end
end
