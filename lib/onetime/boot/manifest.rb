# frozen_string_literal: true

# lib/onetime/boot/manifest.rb
#
# Boot::Manifest provides structured, numbered progress tracking for the
# application boot sequence. It outputs logs in the format:
#   [N/M] Step description
#
# This creates a "systemd-like" boot receipt that helps quickly identify
# which phase of initialization succeeded or failed.
#
module Onetime
  module Boot
    class Manifest
      attr_writer :logger

      # Boot sequence steps in execution order
      # Note: App discovery/registration/warmup happens in config.ru, not boot!
      STEPS = [
        [:logging_setup,    'Configuring logging system'],
        [:diagnostics_init, 'Initializing diagnostics'],
        [:config_load,      'Loading configuration'],
        [:database_init,    'Initializing database connections'],
        [:server_ready,     'Server ready']
      ].freeze

      def initialize(logger = nil)
        @logger = logger
        @completed = []
        @total = STEPS.size
        @start_time = Time.now
      end

      # Log a checkpoint and optionally execute a block, tracking timing
      #
      # @param step_key [Symbol] The step identifier from STEPS
      # @yield Optional block to execute for this step
      # @return [Object] The result of the block, or nil
      def checkpoint(step_key)
        index = STEPS.index { |s| s.first == step_key }
        return unless index

        step_name = STEPS[index].last
        step_start = Time.now

        _logger("[#{index + 1}/#{@total}] #{step_name}")

        result = yield if block_given?

        @completed << step_key
        elapsed = ((Time.now - step_start) * 1000).round(1)

        # Log timing for steps that took longer than 100ms
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
