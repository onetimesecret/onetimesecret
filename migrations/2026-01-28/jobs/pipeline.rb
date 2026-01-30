#!/usr/bin/env ruby
# frozen_string_literal: true

# Kiba ETL Pipeline Orchestrator
#
# Runs all migration phases in sequence with dependency validation.
#
# Execution order:
#   Phase 1: Customer transform (generates email_to_customer_objid lookup)
#   Phase 2: Organization generation (generates email_to_org_objid lookup)
#   Phase 3: CustomDomain transform (generates fqdn_to_domain_objid lookup)
#   Phase 4: Receipt transform (uses all lookups)
#   Phase 5: Secret transform (uses customer/org lookups)
#
# Usage:
#   cd migrations/2026-01-28
#   bundle exec ruby jobs/pipeline.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR    Input directory with dump files (default: ../exports)
#   --output-dir=DIR   Output directory (default: exports)
#   --redis-url=URL    Redis URL (default: redis://127.0.0.1:6379)
#   --temp-db=N        Temp database (default: 15)
#   --dry-run          Parse and count without writing
#   --strict           Filter out records that fail validation
#   --phases=1,2,3     Run specific phases (default: all)
#   --continue         Continue from last successful phase

require 'optparse'
require 'json'
require 'fileutils'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'migration'

class Pipeline
  PHASES = {
    1 => { name: 'Customer', job: '01_customer.rb', input: 'customer_dump.jsonl' },
    2 => { name: 'Organization', job: '02_organization.rb', input: 'customer_transformed.jsonl' },
    3 => { name: 'CustomDomain', job: '03_customdomain.rb', input: 'customdomain_dump.jsonl' },
    4 => { name: 'Receipt', job: '04_receipt.rb', input: 'metadata_dump.jsonl' },
    5 => { name: 'Secret', job: '05_secret.rb', input: 'secret_dump.jsonl' },
  }.freeze

  PHASE_LOOKUPS = {
    1 => %w[email_to_customer_objid],
    2 => %w[email_to_org_objid customer_objid_to_org_objid],
    3 => %w[fqdn_to_domain_objid],
    4 => %w[metadata_key_to_receipt_objid],
    5 => %w[secret_key_to_objid],
  }.freeze

  def initialize(options)
    @input_dir = options[:input_dir]
    @output_dir = options[:output_dir]
    @redis_url = options[:redis_url]
    @temp_db = options[:temp_db]
    @dry_run = options[:dry_run]
    @strict = options[:strict]
    @phases = options[:phases]
    @continue = options[:continue]

    @state_file = File.join(@output_dir, '.pipeline_state.json')
    @results = {}
  end

  def run
    print_header
    validate_prerequisites!
    phases_to_run = determine_phases

    puts "Phases to run: #{phases_to_run.join(', ')}"
    puts

    phases_to_run.each do |phase|
      run_phase(phase)
    end

    print_summary
    save_state
  end

  private

  def print_header
    puts '=' * 60
    puts 'Kiba ETL Migration Pipeline'
    puts '=' * 60
    puts "Input:   #{@input_dir}"
    puts "Output:  #{@output_dir}"
    puts "Mode:    #{@dry_run ? 'DRY RUN' : 'LIVE'}"
    puts "Strict:  #{@strict ? 'YES' : 'NO'}"
    puts
  end

  def validate_prerequisites!
    # Phase 1 needs customer dump
    # Phase 2 needs Phase 1 output
    # Phase 3 needs Phase 2 lookups
    # etc.
  end

  def determine_phases
    return @phases if @phases&.any?

    if @continue && File.exist?(@state_file)
      state = JSON.parse(File.read(@state_file), symbolize_names: true)
      last_completed = state[:last_completed_phase] || 0
      (last_completed + 1..5).to_a
    else
      (1..5).to_a
    end
  end

  def run_phase(phase)
    config = PHASES[phase]
    puts "-" * 50
    puts "Phase #{phase}: #{config[:name]}"
    puts "-" * 50

    # Check input exists
    input_file = resolve_input_file(phase, config[:input])
    unless File.exist?(input_file)
      puts "  SKIPPED: Input file not found: #{input_file}"
      @results[phase] = { status: :skipped, reason: 'input_not_found' }
      return
    end

    # Check prerequisite lookups
    missing_lookups = check_prerequisite_lookups(phase)
    if missing_lookups.any?
      puts "  SKIPPED: Missing prerequisite lookups: #{missing_lookups.join(', ')}"
      @results[phase] = { status: :skipped, reason: 'missing_lookups', lookups: missing_lookups }
      return
    end

    # Build command
    job_file = File.join(__dir__, config[:job])
    cmd = build_command(job_file, input_file)

    puts "  Running: ruby #{config[:job]}"
    puts "  Input: #{input_file}"
    puts

    start_time = Time.now
    success = system(cmd)
    elapsed = Time.now - start_time

    if success
      puts
      puts "  COMPLETED in #{elapsed.round(2)}s"
      @results[phase] = { status: :completed, elapsed: elapsed }
    else
      puts
      puts "  FAILED after #{elapsed.round(2)}s"
      @results[phase] = { status: :failed, elapsed: elapsed }
      raise "Phase #{phase} failed" unless @dry_run
    end
  end

  def resolve_input_file(phase, relative_path)
    if phase == 1
      # Phase 1 reads from original dump directory
      File.join(@input_dir, relative_path)
    elsif phase == 2
      # Phase 2 reads Phase 1 output
      File.join(@output_dir, relative_path)
    else
      # Phases 3-5 read from original dump directory
      File.join(@input_dir, relative_path)
    end
  end

  def check_prerequisite_lookups(phase)
    return [] if phase == 1

    required = (1...phase).flat_map { |p| PHASE_LOOKUPS[p] }
    missing = []

    required.each do |lookup|
      lookup_file = File.join(@output_dir, 'lookups', "#{lookup}.json")
      missing << lookup unless File.exist?(lookup_file)
    end

    missing
  end

  def build_command(job_file, input_file)
    parts = ['bundle', 'exec', 'ruby', job_file]
    parts << "--input-file=#{input_file}"
    parts << "--output-dir=#{@output_dir}"
    parts << "--redis-url=#{@redis_url}"
    parts << "--temp-db=#{@temp_db}"
    parts << '--dry-run' if @dry_run
    parts << '--strict' if @strict
    parts.join(' ')
  end

  def print_summary
    puts
    puts '=' * 60
    puts 'Pipeline Summary'
    puts '=' * 60

    @results.each do |phase, result|
      config = PHASES[phase]
      status = case result[:status]
               when :completed then 'COMPLETED'
               when :failed then 'FAILED'
               when :skipped then "SKIPPED (#{result[:reason]})"
               end
      elapsed = result[:elapsed] ? " (#{result[:elapsed].round(2)}s)" : ''
      puts "  Phase #{phase} (#{config[:name]}): #{status}#{elapsed}"
    end

    completed = @results.count { |_, r| r[:status] == :completed }
    puts
    puts "Completed: #{completed}/#{@results.size} phases"

    # List generated lookups
    lookups_dir = File.join(@output_dir, 'lookups')
    if Dir.exist?(lookups_dir)
      lookups = Dir.glob(File.join(lookups_dir, '*.json')).map { |f| File.basename(f) }
      if lookups.any?
        puts
        puts 'Generated lookups:'
        lookups.each { |l| puts "  - #{l}" }
      end
    end
  end

  def save_state
    last_completed = @results.select { |_, r| r[:status] == :completed }.keys.max || 0

    state = {
      last_completed_phase: last_completed,
      completed_at: Time.now.iso8601,
      results: @results,
    }

    FileUtils.mkdir_p(File.dirname(@state_file))
    File.write(@state_file, JSON.pretty_generate(state))
  end
end

def parse_args(args)
  migration_dir = File.expand_path('..', __dir__)
  results_dir = File.join(migration_dir, 'results')

  options = {
    input_dir: results_dir,
    output_dir: results_dir,
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
    dry_run: false,
    strict: false,
    phases: nil,
    continue: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby jobs/pipeline.rb [OPTIONS]'
    opts.separator ''
    opts.separator 'Kiba ETL pipeline orchestrator - runs all migration phases.'
    opts.separator ''
    opts.separator 'Options:'

    opts.on('--input-dir=DIR', 'Input directory with dump files') do |dir|
      options[:input_dir] = File.expand_path(dir, migration_dir)
    end

    opts.on('--output-dir=DIR', 'Output directory') do |dir|
      options[:output_dir] = File.expand_path(dir, migration_dir)
    end

    opts.on('--redis-url=URL', 'Redis URL (default: redis://127.0.0.1:6379)') do |url|
      options[:redis_url] = url
    end

    opts.on('--temp-db=N', Integer, 'Temp database (default: 15)') do |db|
      options[:temp_db] = db
    end

    opts.on('--dry-run', 'Parse and count without writing') do
      options[:dry_run] = true
    end

    opts.on('--strict', 'Filter out records that fail validation') do
      options[:strict] = true
    end

    opts.on('--phases=LIST', 'Run specific phases (e.g., 1,2,3)') do |list|
      options[:phases] = list.split(',').map(&:to_i)
    end

    opts.on('--continue', 'Continue from last successful phase') do
      options[:continue] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      puts
      puts 'Phases:'
      puts '  1: Customer transform'
      puts '  2: Organization generation'
      puts '  3: CustomDomain transform'
      puts '  4: Receipt transform'
      puts '  5: Secret transform'
      exit 0
    end
  end

  parser.parse!(args)
  options
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  warn e.message
  warn 'Use --help for usage information'
  exit 1
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)
  Pipeline.new(options).run
end
