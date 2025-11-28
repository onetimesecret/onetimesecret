# migrations/20250727-1523_01_convert_symbol_keys.rb
#
# frozen_string_literal: true

# Migration 1 of 2: Convert YAML Symbol Keys to Strings
#
# This migration converts YAML files that use Ruby symbol syntax for keys
# (e.g., `:key:`) to standard string keys (e.g., `key:`).
#
# **NOTE**: Uses `perl` for regex replacement to preserve YAML structure,
# comments, and formatting.
#
# Usage:
#   ruby migrations/20250727-1523_01_convert_symbol_keys.rb --dry-run  # Preview
#   ruby migrations/20250727-1523_01_convert_symbol_keys.rb --run      # Execute
#
# What it does:
#   1. Creates a timestamped backup of etc/config.yaml
#   2. Converts all symbol keys to string keys in-place
#   3. Validates the conversion succeeded
#
# Symbol patterns converted:
#   - Top-level:  `:key:` → `key:`
#   - Nested:     `  :key:` → `  key:`
#   - Array items: `- :key:` → `- key:`

BASE_PATH = File.expand_path File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(BASE_PATH, 'lib')

require 'onetime'
require 'onetime/migration'
require 'yaml'
require 'fileutils'

module Onetime
  class Migration < BaseMigration
    def prepare
      info('Preparing symbol-to-string key conversion')
      @base_path = BASE_PATH
      @config_file = File.join(@base_path, 'etc', 'defaults', 'config.defaults.yaml')
      @backup_suffix = Time.now.strftime('%Y%m%d%H%M%S')

      debug ''
      debug 'Paths:'
      debug "  Base path: #{@base_path}"
      debug "  Config file: #{@config_file}"
      debug ''
    end

    def migration_needed?
      unless File.exist?(@config_file)
        error "Config file does not exist: #{@config_file}"
        return false
      end

      # Check if there are any symbol keys remaining in the file
      has_symbol_keys?
    end

    def migrate
      run_mode_banner

      unless File.exist?(@config_file)
        error "Config file not found: #{@config_file}"
        return false
      end

      info 'Starting symbol-to-string key conversion'
      info "Config file: #{@config_file}"
      debug ''

      # Step 1: Create backup
      backup_config

      # Step 2: Convert symbols to strings
      convert_symbols_to_strings

      # Step 3: Validate conversion
      success = validate_conversion

      print_summary do
        if success
          info ''
          info 'Symbol-to-string conversion completed successfully'
          info "Config file: #{@config_file}"
          info ''
        else
          error ''
          error 'Conversion failed - check backup file to restore'
          error ''
        end
      end

      success
    end

    private

    def has_symbol_keys?
      content = File.read(@config_file)

      # Check for symbol key patterns:
      # 1. Start of line with optional whitespace, then :key:
      # 2. Array item syntax: - :key:
      symbol_pattern = /^(\s*)(-\s*)?:([a-zA-Z_][a-zA-Z0-9_]*):/

      matches = content.scan(symbol_pattern)

      if matches.any?
        info "Found #{matches.size} symbol key(s) to convert"
        debug "Sample matches: #{matches.first(5).map { |m| ":#{m[2]}:" }.join(', ')}"
        true
      else
        info 'No symbol keys found - config already uses string keys'
        false
      end
    end

    def backup_config
      backup_path = "#{@config_file}.#{@backup_suffix}.bak"

      if File.exist?(backup_path)
        info "Backup already exists: #{backup_path}"
        return
      end

      for_realsies_this_time? do
        FileUtils.cp(@config_file, backup_path)
        track_stat(:backup_created)
        info "Created backup: #{backup_path}"
      end
    end

    def convert_symbols_to_strings
      for_realsies_this_time? do
        # Convert YAML symbol keys to string keys using perl
        # Pattern handles:
        #   - Top-level and nested: ^(\s*):key: → \1key:
        #   - Array items: ^(\s*)(-\s*):key: → \1\2key:
        #
        # Using -i for in-place editing (creates .bak on some systems)
        cmd = <<~SHELL
          perl -i -pe 's/^(\\s*)(-\\s*)?:([a-zA-Z_][a-zA-Z0-9_]*)/\\1\\2\\3/g' '#{@config_file}'
        SHELL

        success = system(cmd)

        unless success
          error 'Failed to convert symbol keys to strings'
          return false
        end

        track_stat(:symbols_converted)
        info 'Converted symbol keys to string keys'
        true
      end
    end

    def validate_conversion
      return true if dry_run?

      info 'Validating conversion...'

      # Check for any remaining symbol keys
      if has_symbol_keys?
        error 'Validation failed: symbol keys still present'
        return false
      end

      # Verify YAML is still valid
      begin
        YAML.safe_load_file(@config_file, permitted_classes: [Symbol])
        info 'Validation passed: YAML is valid and no symbol keys remain'
        true
      rescue Psych::SyntaxError => e
        error "Validation failed: YAML syntax error - #{e.message}"
        false
      end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
