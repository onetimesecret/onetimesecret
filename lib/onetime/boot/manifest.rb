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
    class Manifest
      attr_writer :logger

      # Boot sequence step descriptions
      # Order here is just for documentation - actual numbering is by call order
      STEPS = {
        logging_setup: 'Initializing logging system',
        diagnostics_init: 'Initializing diagnostics',
        config_load: 'Loading configuration',
        database_init: 'Initializing database connections',
        complete: 'Initialization complete',
      }.freeze

      def initialize(logger = nil)
        @logger       = logger
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
        prefix = "[#{@current_step}/#{@total}]"
        suffix = suffix ? "(#{suffix})" : ''

        step_start     = Onetime.now_in_μs

        _logger("#{prefix} #{step_name} #{suffix}")

        result = yield if block_given?

        elapsed = Onetime.now_in_μs - step_start
        if elapsed > 100 && @logger
          @logger.debug "#{prefix} Completed in #{elapsed}μs"
        end

        result
      end

      # Mark the boot sequence as complete and log total time
      def complete!
        elapsed = Onetime.now_in_μs - @start_time
        elapsed = (elapsed / 1000.0).round # Convert to ms
        checkpoint(:complete, "in #{elapsed}ms")
      end

      private

      def _logger(msg)
        if @logger
          @logger.info msg
        else
          warn msg
        end
      end
    end
  end
end
