# lib/onetime/boot/manifest.rb
#
# frozen_string_literal: true

#
# Boot::Manifest provides structured, numbered progress tracking for the
# application boot sequence. It outputs logs in the format:
#   [N/M] Step description
#
# Checkpoints are numbered in the order they're called, not by predefined order.
#
module Onetime
  module Boot
    # Development-time error for incomplete boot sequences
    # Not rescued by boot.rb handlers since it indicates a code bug
    class IncompleteSequenceError < StandardError; end

    class Manifest
      # Boot sequence step descriptions
      # Order here is just for documentation - actual numbering is by call order
      STEPS = {
        logging_setup: 'Initializing logging system',
        diagnostics_init: 'Initializing diagnostics',
        config_load: 'Loading configuration',
        database_init: 'Initializing database connections',
      }.freeze

      # Completion message (not counted as a step)
      COMPLETE_MESSAGE = 'Initialization complete'

      def initialize
        @logger       = Logger.new($stderr)
        @logger.level = Logger::INFO  # Show checkpoints, hide debug noise
        @logger.formatter = proc do |severity, _datetime, _progname, msg|
          "#{msg}\n"  # Minimal format - just the message
        end
        @current_step = 0
        @total        = STEPS.size
        @start_time   = Onetime.now_in_μs
      end

      # Log a checkpoint and optionally execute a block, tracking timing
      #
      # @param step_key [Symbol] The step identifier from STEPS
      # @yield Optional block to execute for this step
      # @return [Object] The result of the block, or nil
      def checkpoint(step_key, suffix = nil)
        step_name = STEPS[step_key]
        return unless step_name

        @current_step += 1
        prefix         = "[#{@current_step}/#{@total}]"
        suffix         = suffix ? "(#{suffix})" : ''
        step_start     = Onetime.now_in_μs

        _logger.debug("#{prefix} #{step_name} #{suffix}")

        result = yield if block_given?

        elapsed_ms = _elapsed_in_ms(step_start)

        # Log anything that takes longer than 0.1 seconds
        @logger.debug "#{prefix} #{step_name} #{elapsed_ms}ms" if elapsed_ms > 100

        result
      end

      # Mark the boot sequence as complete and log total time
      #
      # Validates all steps were called before logging completion.
      # Closes the temporary logger after logging completion to release
      # file descriptors and allow GC to reclaim memory.
      def complete!
        # Validate all steps completed BEFORE logging success
        if @current_step != @total
          raise IncompleteSequenceError, "Boot sequence incomplete: #{@current_step} of #{@total} steps completed"
        end

        _logger.info("#{COMPLETE_MESSAGE} (in #{_elapsed_in_ms}ms)")

        # Don't close the logger since it writes to $stderr which puma needs
        # Just nil it out so SemanticLogger takes over
        @logger = nil
      end

      private

      # Our own private Idaho
      def _logger
        @logger
      end

      def _elapsed(start_time=nil)
        Onetime.now_in_μs - (start_time || @start_time)
      end

      def _elapsed_in_ms(start_time=nil)
        (_elapsed(start_time) / 1000.0).round
      end
    end
  end
end
