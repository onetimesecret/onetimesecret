#!/usr/bin/env ruby
# frozen_string_literal: true

# Migration Pipeline Orchestrator
#
# Runs the complete v1→v2 migration pipeline:
# 1. Transform: Parse JSONL exports, apply transformations
# 2. Validate Pre-load: Check transformed data integrity
# 3. Load: RESTORE keys to Valkey
# 4. Rebuild Indexes: Create v2 index structures
# 5. Validate Post-load: Verify migration success
#
# Usage:
#   ruby scripts/migrations/jan24/run_migration.rb [OPTIONS]
#
# Options:
#   --step=STEP        Run specific step: transform, validate-pre, load, indexes, validate-post
#   --exports-dir=DIR  Exports directory (default: exports)
#   --valkey-url=URL   Valkey URL (default: redis://127.0.0.1:6379/0)
#   --replace          Replace existing keys during load
#   --dry-run          Show what would be done without writing
#
# Environment:
#   SOURCE_REDIS_URL   Source Redis URL for dump (if re-dumping)
#   TARGET_VALKEY_URL  Target Valkey URL for load

require 'fileutils'

class MigrationPipeline
  SCRIPTS_DIR = File.dirname(__FILE__)

  STEPS = %w[
    transform
    validate-pre
    load
    indexes
    validate-post
  ].freeze

  def initialize(options)
    @options     = options
    @exports_dir = options[:exports_dir]
    @valkey_url  = options[:valkey_url]
    @replace     = options[:replace]
    @dry_run     = options[:dry_run]
    @step        = options[:step]
  end

  def run
    puts banner
    puts

    steps_to_run = @step ? [@step] : STEPS

    steps_to_run.each do |step|
      puts '=' * 60
      puts "STEP: #{step.upcase}"
      puts '=' * 60
      puts

      success = case step
                when 'transform'
                  run_transform
                when 'validate-pre'
                  run_validate_pre
                when 'load'
                  run_load
                when 'indexes'
                  run_indexes
                when 'validate-post'
                  run_validate_post
                else
                  puts "Unknown step: #{step}"
                  false
                end

      unless success
        puts "\nStep '#{step}' failed. Stopping pipeline."
        exit 1
      end

      puts "\nStep '#{step}' completed successfully."
      puts
    end

    puts banner('MIGRATION COMPLETE')
  end

  private

  def run_transform
    cmd = build_cmd(
      'transform_keys.rb',
      "--input-dir=#{@exports_dir}",
      @dry_run ? '--dry-run' : nil,
    )

    run_script(cmd)
  end

  def run_validate_pre
    cmd = build_cmd(
      'validate_keys.rb',
      '--mode=pre-load',
      "--input-dir=#{@exports_dir}",
      "--valkey-url=#{@valkey_url}",
    )

    run_script(cmd)
  end

  def run_load
    if @dry_run
      puts "DRY RUN: Would load to #{@valkey_url}"
      puts "  Replace mode: #{@replace}"
      return true
    end

    cmd = build_cmd(
      'load_keys.rb',
      "--input-dir=#{@exports_dir}",
      "--valkey-url=#{@valkey_url}",
      @replace ? '--replace' : nil,
    )

    run_script(cmd)
  end

  def run_indexes
    if @dry_run
      puts "DRY RUN: Would rebuild indexes on #{@valkey_url}"
      return true
    end

    cmd = build_cmd(
      'rebuild_indexes.rb',
      "--valkey-url=#{@valkey_url}",
    )

    run_script(cmd)
  end

  def run_validate_post
    cmd = build_cmd(
      'validate_keys.rb',
      '--mode=post-load',
      "--input-dir=#{@exports_dir}",
      "--valkey-url=#{@valkey_url}",
    )

    run_script(cmd)
  end

  def build_cmd(script, *args)
    script_path = File.join(SCRIPTS_DIR, script)
    ['ruby', script_path, *args.compact]
  end

  def run_script(cmd)
    puts "Running: #{cmd.join(' ')}"
    puts

    system(*cmd)
  end

  def banner(text = 'V1 → V2 DATA MIGRATION PIPELINE')
    [
      '=' * 60,
      text.center(60),
      '=' * 60,
    ].join("\n")
  end
end

def parse_args(args)
  options = {
    exports_dir: 'exports',
    valkey_url: ENV['TARGET_VALKEY_URL'] || 'redis://127.0.0.1:6379/0',
    replace: false,
    dry_run: false,
    step: nil,
  }

  args.each do |arg|
    case arg
    when /^--step=(.+)$/
      options[:step] = Regexp.last_match(1)
    when /^--exports-dir=(.+)$/
      options[:exports_dir] = Regexp.last_match(1)
    when /^--valkey-url=(.+)$/
      options[:valkey_url] = Regexp.last_match(1)
    when '--replace'
      options[:replace] = true
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        V1 → V2 Data Migration Pipeline

        Usage: ruby scripts/migrations/jan24/run_migration.rb [OPTIONS]

        Options:
          --step=STEP        Run specific step:
                               transform     - Parse and transform JSONL exports
                               validate-pre  - Validate transformed data before load
                               load          - RESTORE keys to Valkey
                               indexes       - Rebuild v2 index structures
                               validate-post - Validate migration success
          --exports-dir=DIR  Exports directory (default: exports)
          --valkey-url=URL   Valkey URL (default: redis://127.0.0.1:6379/0)
          --replace          Replace existing keys during load
          --dry-run          Show what would be done without writing
          --help             Show this help

        Environment Variables:
          SOURCE_REDIS_URL   Source Redis URL for dump operations
          TARGET_VALKEY_URL  Target Valkey URL (overrides --valkey-url)

        Examples:
          # Run full pipeline (dry run)
          ruby scripts/migrations/jan24/run_migration.rb --dry-run

          # Run only transform step
          ruby scripts/migrations/jan24/run_migration.rb --step=transform

          # Run full pipeline with replace
          ruby scripts/migrations/jan24/run_migration.rb --replace

          # Run against specific Valkey instance
          ruby scripts/migrations/jan24/run_migration.rb --valkey-url=redis://valkey:6379/0
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  pipeline = MigrationPipeline.new(options)
  pipeline.run
end
