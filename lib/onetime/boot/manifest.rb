# lib/onetime/boot/manifest.rb
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
        logging_setup:    'Configuring logging system',
        diagnostics_init: 'Initializing diagnostics',
        config_load:      'Loading configuration',
        database_init:    'Initializing database connections',
        server_ready:     'Initialization complete'
      }.freeze

      def initialize(logger = nil)
        @logger = logger
        @current_step = 0
        @total = STEPS.size
        @start_time = Time.now
      end

      # Log a checkpoint and optionally execute a block, tracking timing
      #
      # @param step_key [Symbol] The step identifier from STEPS
      # @yield Optional block to execute for this step
      # @return [Object] The result of the block, or nil
      def checkpoint(step_key)
        step_name = STEPS[step_key]
        return unless step_name

        @current_step += 1
        step_start = Time.now
        _logger("[#{@current_step}/#{@total}] #{step_name}")

        result = yield if block_given?

        elapsed = ((Time.now - step_start) * 1000).round(1)
        if elapsed > 100 && @logger
          @logger.debug "Completed #{step_name} in #{elapsed}ms"
        end

        result
      end

      # Mark the boot sequence as complete and log total time
      def complete!
        elapsed = ((Time.now - @start_time) * 1000).round(1)
        _logger("Boot sequence complete in #{elapsed}ms")
      end

      private

      def _logger(msg)
        if @logger
          @logger.info msg
        else
          $stderr.puts msg
        end
      end
    end
  end
end
