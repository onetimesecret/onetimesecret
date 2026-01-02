# lib/onetime/boot/ticker_tape.rb
#
# frozen_string_literal: true

# Boot Ticker Tape
#
# TracePoint-based execution trace for boot debugging.
#
# Captures only method calls (no returns/ends) in JSONL format with
# run-length encoding for consecutive duplicates.
#
# ## Usage
#
# ```bash
# # Trace boot
# BOOT_TICKER_TAPE=1 bundle exec puma -p 3000
# BOOT_TICKER_TAPE=1 bundle exec bin/ots jobs worker
#
# # Analyze output
# bin/analyze-boot-trace tmp/boot_ticker_tape_*.jsonl
# bin/analyze-boot-trace tmp/boot_ticker_tape_*.jsonl --rabbitmq
# bin/analyze-boot-trace tmp/boot_ticker_tape_*.jsonl --initializers
# ```
#
# Output: `tmp/boot_ticker_tape_<timestamp>.jsonl`
#
# ## Filtering
#
# Customize in constants below:
# - `FILTERED_NAMESPACES` - Exclude entire namespaces (JSON, YAML, etc.)
# - `FILTERED_SIGNATURES` - Exclude specific methods (*#initialize, Hash#*, etc.)
#
# ## Options
#
# - `TICKER_TAPE_BINDINGS=1` - Capture local variables (slower)
#
# ## See
#
# - `lib/onetime/boot/TICKER-TAPE.md` - Full documentation
# - `bin/analyze-boot-trace` - Analysis tool
#
module Onetime
  module Boot
    class TickerTape
      # Only trace method calls - returns/ends are just noise

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
        'Onetime::Utils'
      ].freeze

      # Namespaces to exclude from tracing (stdlib/gems that create noise)
      FILTERED_NAMESPACES = [
        'JSON',
        'YAML',
        'Psych',
        'ERB',
        'CGI',
        'URI',
        'Net',
        'OpenSSL',
        'Digest',
        'Base64',
        'StringIO',
        'Tempfile',
        'FileUtils',
        'Logger',
        'Monitor',
        'Mutex',
        'Onetime::Utils::Enumerable',
      ].freeze

      # Specific method signatures to exclude (pattern matching)
      # Supports glob-style wildcards: * (any chars), ? (single char)
      FILTERED_SIGNATURES = [
        '*#initialize',           # All constructors
        'Onetime::Boot::Initializer.initialize_name',           # Onetime::Boot::Initializer.initialize_name
        'Onetime::Boot::Initializer#name',
        '*#inspect',              # Inspection methods
        '*#to_s',                 # String conversion
        '*#to_str',               # String coercion
        '*#hash',                 # Hash value calculation
        '*#eql?',                 # Equality checks
        '*#==',                   # Equality operators
        'Hash#*',                 # All Hash methods (noisy)
        'Array#*',                # All Array methods (noisy)
        'String#*',               # All String methods (noisy)
        'Kernel#*',               # All Kernel methods (noisy)
        'BasicObject#*',          # All BasicObject methods
        'Module#*',               # Module introspection
        'Class#*',                # Class introspection
      ].freeze

      attr_reader :events, :output_file

      def initialize
        @events           = []
        @start_time       = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        @trace            = nil
        @mutex            = Mutex.new
        @tracing_self     = false # Prevent infinite recursion
        @capture_bindings = ENV['TICKER_TAPE_BINDINGS'] == '1' # Opt-in binding capture
      end

      def start
        @trace = TracePoint.new(:call) do |tp| # Only trace calls
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

            sig = method_signature(tp)

            # Skip filtered signatures
            next if filtered_signature?(sig)

            # Deduplicate consecutive calls - increment reps instead of new line
            if @events.last && @events.last[:sig] == sig
              @events.last[:reps] += 1
              @events.last[:dur] = elapsed_μs - @events.last[:ts]
            else
              event = {
                ts: elapsed_μs,
                sig: sig,
                path: safe_path(tp.path),
                line: tp.lineno,
                reps: 1,
              }

              # Only add binding if enabled and present
              if @capture_bindings
                locals = extract_locals(tp.binding)
                event[:bind] = locals unless locals.empty?
              end

              record_event(event)
            end
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

        # Check if class is in filtered namespaces
        klass_name = tp.defined_class.to_s
        return false if FILTERED_NAMESPACES.any? { |ns| klass_name.start_with?(ns) }

        # Only trace our code
        path.include?('/onetime/') ||
          klass_name.start_with?('Onetime', 'OT')
      end

      # Check if signature matches any filtered pattern
      # Supports glob-style wildcards: * (any chars), ? (single char)
      def filtered_signature?(sig)
        FILTERED_SIGNATURES.any? do |pattern|
          # Convert glob pattern to regex
          # Escape special regex chars except * and ?
          regex_pattern = Regexp.escape(pattern)
            .gsub('\*', '.*')   # * matches any chars
            .gsub('\?', '.')    # ? matches single char

          sig.match?(/\A#{regex_pattern}\z/)
        end
      end

      # Format method signature as Ruby convention
      # Class#instance_method or Module.module_method
      def method_signature(tp)
        klass_str = safe_class_name(tp.defined_class)
        method = tp.method_id

        # Detect singleton class (class methods)
        # Singleton classes appear as "#<Class:ClassName>"
        if klass_str.start_with?('#<Class:')
          # Extract actual class name and use . for class method
          klass_name = klass_str[8..-2] # Remove "#<Class:" and ">"
          "#{klass_name}.#{method}"
        else
          # Instance method
          "#{klass_str}##{method}"
        end
      rescue
        "#{klass_str}##{method}" # fallback to instance method notation
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
        @output_file = "tmp/boot_ticker_tape_#{Time.now.to_i}.jsonl"

        # Ensure tmp directory exists
        FileUtils.mkdir_p('tmp')

        # Write JSONL format (one JSON object per line)
        File.open(output_file, 'w') do |f|
          # Header line with metadata
          f.puts JSON.generate({
            meta: true,
            instance: Onetime.instance,
            events: @events.size,
            duration_ms: elapsed_μs / 1000.0,
            bindings: @capture_bindings,
            ts: Time.now.iso8601,
          })

          # Event lines (compact format)
          @events.each do |event|
            f.puts JSON.generate(event)
          end
        end

        puts "\n📼 Boot ticker tape written to: #{output_file}"
        puts "   Total events: #{@events.size}"
        puts "   Duration: #{(elapsed_μs / 1000.0).round(2)}ms"
        puts "   Format: JSONL (compact)"
      rescue StandardError => ex
        warn "[TickerTape] Failed to write ticker tape: #{ex.message}"
      end
    end
  end
end
