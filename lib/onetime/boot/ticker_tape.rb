# lib/onetime/boot/ticker_tape.rb
#
# frozen_string_literal: true

# Boot Ticker Tape
#
# TracePoint-based execution trace for boot debugging.
#
# ## Usage
#
# ```bash
# # Trace boot
# BOOT_TICKER_TAPE=1 bundle exec puma -p 3000
# BOOT_TICKER_TAPE=1 bundle exec bin/ots jobs worker
#
# # Analyze output
# bin/analyze-boot-trace tmp/boot_ticker_tape_*.json
# bin/analyze-boot-trace tmp/boot_ticker_tape_*.json --rabbitmq
# bin/analyze-boot-trace tmp/boot_ticker_tape_*.json --initializers
# ```
#
# Output: `tmp/boot_ticker_tape_<timestamp>.json`
#
# ## Example
#
# ```bash
# # Find missing queue declaration
# BOOT_TICKER_TAPE=1 bundle exec bin/ots jobs worker
# bin/analyze-boot-trace tmp/boot_ticker_tape_*.json --rabbitmq | grep -i declare
# ```
#
# ## Options
#
# - `TICKER_TAPE_BINDINGS=1` - Capture local variables (slower)
#
# ## See
#
# - `lib/onetime/boot/ticker_tape.rb`
# - `bin/analyze-boot-trace`
#
module Onetime
  module Boot
    class TickerTape
      EVENTS = [:call, :return, :class, :end, :raise].freeze

      # Objects that are unsafe to inspect during tracing
      UNSAFE_CLASSES = [
        'Bunny::Session',
        'Bunny::Channel',
        'ConnectionPool',
        'Thread',
        'Mutex',
        'Monitor',
        'Queue',
        'ConditionVariable',
      ].freeze

      def initialize
        @events           = []
        @start_time       = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        @trace            = nil
        @mutex            = Mutex.new
        @tracing_self     = false # Prevent infinite recursion
        @capture_bindings = ENV['TICKER_TAPE_BINDINGS'] == '1' # Opt-in binding capture
      end

      def start
        @trace = TracePoint.new(*EVENTS) do |tp|
          # Prevent tracing our own tracing code
          next if @tracing_self

          begin
            @tracing_self = true

            # Filter to only our namespaces
            next unless relevant_event?(tp)

            # Skip threading internals
            next if tp.defined_class.to_s.include?('Thread')
            next if tp.defined_class.to_s.include?('Mutex')
            next if tp.defined_class.to_s.include?('ConnectionPool')

            record_event(
              timestamp: elapsed_μs,
              event: tp.event,
              method: tp.method_id,
              defined_class: safe_class_name(tp.defined_class),
              path: safe_path(tp.path),
              lineno: tp.lineno,
              thread_id: Thread.current.object_id,
              binding: @capture_bindings ? extract_locals(tp.binding) : nil,
            )
          rescue StandardError => ex
            # Silent failure - don't crash boot if tracing fails
            warn "[TickerTape] Trace error: #{ex.class}: #{ex.message}" if OT.debug?
          ensure
            @tracing_self = false
          end
        end
        @trace.enable
      end

      def stop
        @trace&.disable
        write_ticker_tape
      end

      private

      def relevant_event?(tp)
        path = tp.path
        return false if path.include?('/gems/')
        return false if path.include?('/ruby/')
        return false if path.include?('/bundler/')

        # Only trace our code
        path.include?('/onetime/') ||
          tp.defined_class.to_s.start_with?('Onetime', 'OT')
      end

      def elapsed_μs
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - @start_time
      end

      def record_event(data)
        # Thread-safe event recording
        @mutex.synchronize do
          @events << data
        end
      end

      def extract_locals(binding)
        # Capture interesting local variables (safely)
        return {} unless binding

        binding.local_variables.each_with_object({}) do |var, hash|
          next if var.to_s.start_with?('_') # Skip internal vars

          val = binding.local_variable_get(var)

          # Skip unsafe objects
          next if unsafe_object?(val)

          hash[var] = safe_inspect(val)
        end
      rescue StandardError => ex
        { error: "Failed to extract: #{ex.class}" }
      end

      def unsafe_object?(obj)
        return true if obj.nil?

        class_name = obj.class.name
        UNSAFE_CLASSES.any? { |unsafe| class_name&.include?(unsafe) }
      rescue StandardError
        true # If we can't even get the class name, it's unsafe
      end

      def safe_inspect(obj)
        case obj
        when String
          obj.size > 100 ? "#{obj[0..100]}..." : obj
        when Symbol, Integer, Float, TrueClass, FalseClass, NilClass
          obj
        when Array
          obj.size > 5 ? "Array[#{obj.size}]" : obj.map { |x| safe_inspect(x) }
        when Hash
          obj.size > 5 ? "Hash[#{obj.size}]" : obj.transform_values { |v| safe_inspect(v) }
        else
          obj.class.name
        end
      rescue StandardError
        '<?>'
      end

      def safe_class_name(klass)
        klass.to_s
      rescue StandardError
        '<?>'
      end

      def safe_path(path)
        # Shorten paths relative to project root
        path.sub(Onetime::HOME, '.')
      rescue StandardError
        path.to_s
      end

      def write_ticker_tape
        output_file = "tmp/boot_ticker_tape_#{Time.now.to_i}.json"

        data = {
          boot_instance: Onetime.instance,
          total_events: @events.size,
          duration_ms: elapsed_μs / 1000.0,
          capture_bindings: @capture_bindings,
          events: @events,
        }

        # Ensure tmp directory exists
        FileUtils.mkdir_p('tmp')

        File.write(output_file, JSON.pretty_generate(data))

        puts "\n📼 Boot ticker tape written to: #{output_file}"
        puts "   Total events: #{@events.size}"
        puts "   Duration: #{(elapsed_μs / 1000.0).round(2)}ms"
      rescue StandardError => ex
        warn "[TickerTape] Failed to write ticker tape: #{ex.message}"
      end
    end
  end
end
