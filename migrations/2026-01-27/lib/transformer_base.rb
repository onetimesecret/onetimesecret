# migrations/2026-01-27/lib/transformer_base.rb
#
# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'redis_helper'
require_relative 'lookup_registry'
require_relative 'phase_manifest'

module Migration
  # Base class for migration transform scripts.
  #
  # Provides the template method pattern for processing JSONL records:
  # 1. validate_prerequisites! - Ensure required lookups exist
  # 2. process_record - Transform a single record (abstract)
  # 3. register_outputs - Save lookup data and output files
  #
  # Handles common concerns:
  # - CLI argument parsing
  # - Redis connection management
  # - Stats tracking and summary printing
  # - Error accumulation with context
  # - Dry-run support
  #
  # Subclasses implement:
  # - PHASE constant
  # - MODEL_NAME constant
  # - #configure_options (optional, for extra CLI args)
  # - #validate_prerequisites!
  # - #process_record(record)
  # - #register_outputs (optional, for lookup generation)
  #
  # Usage:
  #   class CustomerTransformer < Migration::TransformerBase
  #     PHASE = 1
  #     MODEL_NAME = 'customer'
  #
  #     def validate_prerequisites!
  #       # Nothing required for phase 1
  #     end
  #
  #     def process_record(record)
  #       # Transform and return V2 records
  #     end
  #   end
  #
  #   CustomerTransformer.new.run(ARGV)
  #
  class TransformerBase
    # Subclasses must define these
    PHASE = nil
    MODEL_NAME = nil

    # Base directory for this migration (relative to script location)
    MIGRATION_DIR = File.expand_path('..', __dir__)
    RESULTS_DIR = File.join(MIGRATION_DIR, 'results')

    # Common CLI options available to all transformers
    DEFAULT_OPTIONS = {
      input_file: nil,       # Set in subclass based on MODEL_NAME
      output_dir: nil,       # Set in subclass based on MODEL_NAME
      results_dir: RESULTS_DIR,
      redis_url: 'redis://127.0.0.1:6379',
      temp_db: 15,
      dry_run: false,
    }.freeze

    attr_reader :options, :stats, :redis_helper, :lookup_registry, :manifest

    def initialize
      @options = DEFAULT_OPTIONS.dup
      @stats = default_stats
      @redis_helper = nil
      @lookup_registry = nil
      @manifest = nil
      @v2_records = []
    end

    # Main entry point. Parses args, runs transformation, prints summary.
    #
    # @param args [Array<String>] Command-line arguments
    # @return [Hash] Stats hash
    #
    def run(args = ARGV)
      parse_args(args)
      setup_defaults
      validate_input_file!
      initialize_services

      puts "Phase #{self.class::PHASE}: #{self.class::MODEL_NAME} transformation"
      puts "Input: #{@options[:input_file]}"
      puts "Output: #{@options[:output_dir]}"
      puts 'Mode: DRY RUN' if @options[:dry_run]
      puts

      validate_prerequisites!

      connect_redis unless @options[:dry_run]
      process_input_file
      write_output unless @options[:dry_run]
      register_outputs unless @options[:dry_run]
      update_manifest unless @options[:dry_run]

      print_summary
      @stats
    ensure
      cleanup
    end

    protected

    # Override in subclass to validate required lookups exist.
    # Should use @lookup_registry.require_lookup(:name, for_phase: PHASE)
    #
    def validate_prerequisites!
      # Default: no prerequisites
    end

    # Override in subclass to transform a single record.
    #
    # @param record [Hash] Parsed JSONL record (symbolized keys)
    # @return [Array<Hash>] Array of V2 records to write
    #
    def process_record(record)
      raise NotImplementedError, "Subclass must implement #process_record"
    end

    # Override in subclass to enable grouping mode.
    #
    # When this returns a non-nil value, records are accumulated by grouping
    # key and then processed together via #process_group. This is useful for
    # models with related records that should be processed together.
    #
    # @param record [Hash] Parsed JSONL record (symbolized keys)
    # @return [String, nil] Grouping key, or nil to disable grouping for this record
    #
    def grouping_key_for(record)
      nil # Default: no grouping
    end

    # Override in subclass to process a group of related records.
    #
    # Called when grouping mode is enabled (grouping_key_for returns non-nil).
    # Receives all records that share the same grouping key.
    #
    # @param key [String] The grouping key
    # @param records [Array<Hash>] All records with this grouping key
    # @return [Array<Hash>] Array of V2 records to write
    #
    def process_group(key, records)
      raise NotImplementedError, "Subclass must implement #process_group when using grouping mode"
    end

    # Override in subclass to register output lookups.
    # Called after all records are processed.
    #
    def register_outputs
      # Default: no outputs to register
    end

    # Override in subclass to add custom CLI options.
    #
    # @param parser [OptionParser] The option parser to configure
    #
    def configure_options(parser)
      # Default: no custom options
    end

    # Override in subclass to customize the help text.
    #
    def help_text
      <<~HELP
        Usage: ruby #{$PROGRAM_NAME} [OPTIONS]

        Transforms #{self.class::MODEL_NAME} data from V1 dump to V2 format.
        Phase #{self.class::PHASE} of the migration pipeline.

        Options:
          --input-file=FILE   Input JSONL dump file
          --output-dir=DIR    Output directory
          --results-dir=DIR   Base results directory (default: migrations/2026-01-27/results)
          --redis-url=URL     Redis URL for temp operations (default: redis://127.0.0.1:6379)
          --temp-db=N         Temp database number (default: 15)
          --dry-run           Parse and count without writing output
          --help              Show this help
      HELP
    end

    # Initialize stats hash. Override to add model-specific stats.
    #
    def default_stats
      {
        records_read: 0,
        records_written: 0,
        records_processed: 0,
        records_skipped: 0,
        errors: [],
      }
    end

    # Track an error with context.
    #
    # @param context [Hash] Error context (e.g., { key: record[:key] })
    # @param message [String] Error message
    #
    def track_error(context, message)
      @stats[:errors] << context.merge(error: message)
    end

    # Increment a stat counter.
    #
    # @param key [Symbol] Stat key
    # @param amount [Integer] Amount to increment (default: 1)
    #
    def increment_stat(key, amount = 1)
      @stats[key] ||= 0
      @stats[key] += amount
    end

    # Track a hash stat (for things like role counts).
    #
    # @param key [Symbol] Stat key
    # @param subkey [String] Sub-key to increment
    #
    def track_stat_hash(key, subkey)
      @stats[key] ||= Hash.new(0)
      @stats[key][subkey] += 1
    end

    # Convenience: restore and read a hash from a record.
    #
    def restore_hash(record)
      @redis_helper.restore_and_read_hash(record)
    end

    # Convenience: create a DUMP from transformed fields.
    #
    def create_dump(fields)
      @redis_helper.create_dump_from_hash(fields)
    end

    # Convenience: perform a lookup.
    #
    def lookup(name, key)
      @lookup_registry.lookup(name, key)
    end

    # Convenience: perform a lookup with failure tracking.
    #
    def lookup_tracked(name, key, stats_key)
      @lookup_registry.lookup_with_tracking(
        name, key,
        stats: @stats,
        stats_key: stats_key
      )
    end

    private

    def setup_defaults
      model = self.class::MODEL_NAME
      results_dir = @options[:results_dir]
      @options[:input_file] ||= File.join(results_dir, "#{model}_dump.jsonl")
      @options[:output_dir] ||= results_dir
    end

    def validate_input_file!
      unless File.exist?(@options[:input_file])
        raise ArgumentError, "Input file not found: #{@options[:input_file]}"
      end
    end

    def initialize_services
      @redis_helper = RedisHelper.new(
        redis_url: @options[:redis_url],
        temp_db: @options[:temp_db]
      )
      @lookup_registry = LookupRegistry.new(results_dir: @options[:results_dir])
      @manifest = PhaseManifest.new(results_dir: @options[:results_dir])
    end

    def connect_redis
      @redis_helper.connect!
    end

    def process_input_file
      # First pass: detect if grouping mode is needed by checking first record
      first_record = peek_first_record
      @grouping_mode = first_record && grouping_key_for(first_record)

      if @grouping_mode
        process_with_grouping
      else
        process_without_grouping
      end
    end

    def peek_first_record
      File.open(@options[:input_file]) do |f|
        line = f.readline.strip
        return nil if line.empty?
        JSON.parse(line, symbolize_names: true)
      end
    rescue EOFError, JSON::ParserError
      nil
    end

    def process_without_grouping
      File.foreach(@options[:input_file]) do |line|
        @stats[:records_read] += 1
        process_line(line.strip)
      end
    end

    def process_with_grouping
      groups = Hash.new { |h, k| h[k] = [] }

      # Accumulate records by grouping key
      File.foreach(@options[:input_file]) do |line|
        @stats[:records_read] += 1
        next if line.strip.empty?

        begin
          record = JSON.parse(line.strip, symbolize_names: true)
          key = grouping_key_for(record)
          if key
            groups[key] << record
          else
            # Process ungrouped records immediately
            results = process_record(record)
            @v2_records.concat(Array(results))
            @stats[:records_processed] += 1
          end
        rescue JSON::ParserError => ex
          track_error({ line: @stats[:records_read] }, "JSON parse error: #{ex.message}")
        rescue StandardError => ex
          track_error({ line: @stats[:records_read] }, "Processing error: #{ex.message}")
        end
      end

      # Process accumulated groups
      groups.each do |key, records|
        begin
          results = process_group(key, records)
          @v2_records.concat(Array(results))
          increment_stat(:groups_processed)
          increment_stat(:related_records, records.size - 1) # -1 for the object record
        rescue StandardError => ex
          track_error({ group_key: key }, "Group processing error: #{ex.message}")
        end
      end
    end

    def process_line(line)
      return if line.empty?

      record = JSON.parse(line, symbolize_names: true)
      results = process_record(record)
      @v2_records.concat(Array(results))
      @stats[:records_processed] += 1
    rescue JSON::ParserError => ex
      track_error({ line: @stats[:records_read] }, "JSON parse error: #{ex.message}")
    rescue StandardError => ex
      track_error({ line: @stats[:records_read] }, "Processing error: #{ex.message}")
    end

    def write_output
      FileUtils.mkdir_p(@options[:output_dir])
      output_file = File.join(@options[:output_dir], output_filename)

      File.open(output_file, 'w') do |f|
        @v2_records.each do |record|
          f.puts(JSON.generate(record))
          @stats[:records_written] += 1
        end
      end

      puts "Wrote #{@stats[:records_written]} records to #{output_file}"
    end

    def output_filename
      "#{self.class::MODEL_NAME}_transformed.jsonl"
    end

    def update_manifest
      @manifest.complete_phase(
        phase: self.class::PHASE,
        name: self.class::MODEL_NAME,
        records_in: @stats[:records_read],
        records_out: @stats[:records_written],
        errors: @stats[:errors].size
      )
    end

    def cleanup
      @redis_helper&.cleanup_temp_keys!
      @redis_helper&.disconnect!
    end

    def print_summary
      puts
      puts "=== #{self.class::MODEL_NAME.capitalize} Transformation Summary ==="
      puts "Phase: #{self.class::PHASE}"
      puts "Input file: #{@options[:input_file]}"
      puts "Records read: #{@stats[:records_read]}"
      puts "Records processed: #{@stats[:records_processed]}"
      puts "Records skipped: #{@stats[:records_skipped]}"
      puts "Records written: #{@stats[:records_written]}"

      print_custom_stats

      if @stats[:errors].any?
        puts
        puts "Errors (#{@stats[:errors].size}):"
        @stats[:errors].first(10).each { |err| puts "  - #{err}" }
        puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
      end
    end

    # Override to print model-specific stats.
    #
    def print_custom_stats
      # Default: nothing extra
    end

    def parse_args(args)
      args.each do |arg|
        case arg
        when /^--input-file=(.+)$/
          @options[:input_file] = Regexp.last_match(1)
        when /^--output-dir=(.+)$/
          @options[:output_dir] = Regexp.last_match(1)
        when /^--results-dir=(.+)$/
          @options[:results_dir] = Regexp.last_match(1)
        when /^--redis-url=(.+)$/
          @options[:redis_url] = Regexp.last_match(1)
        when /^--temp-db=(\d+)$/
          @options[:temp_db] = Regexp.last_match(1).to_i
        when '--dry-run'
          @options[:dry_run] = true
        when '--help', '-h'
          puts help_text
          exit 0
        else
          parse_custom_arg(arg) || unknown_arg(arg)
        end
      end
    end

    # Override to handle custom arguments.
    # @return [Boolean] true if handled, false otherwise
    #
    def parse_custom_arg(arg)
      false
    end

    def unknown_arg(arg)
      warn "Unknown option: #{arg}"
      exit 1
    end
  end
end
