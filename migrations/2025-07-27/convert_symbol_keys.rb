# migrations/2025-07-27/convert_symbol_keys.rb
#
# frozen_string_literal: true

# DEPRECATED: REFERENCE ONLY - DO NOT EXECUTE
# Use the 2026-01-26 migration scripts instead.
#
# ---
#
# Migration 1 of 2: Convert YAML Symbol Keys to Strings
#
# This migration converts YAML files that use Ruby symbol syntax for keys
# (e.g., `:key:`) to standard string keys (e.g., `key:`).
#
# **NOTE**: Uses `perl` for regex replacement to preserve YAML structure,
# comments, and formatting.
#
# Usage:
#   bin/ots migrate 20250727-1523_01_convert_symbol_keys.rb           # Preview changes
#   bin/ots migrate --run 20250727-1523_01_convert_symbol_keys.rb     # Execute migration
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
require 'yaml'
require 'fileutils'
require 'familia/migration'

module Onetime
  module Migrations
    # Convert YAML symbol keys to string keys in config files
    class ConvertSymbolKeys < Familia::Migration::Base
      self.migration_id = '20250727_01_convert_symbol_keys'
      self.description = 'Convert YAML symbol keys (:key:) to string keys (key:)'
      self.dependencies = []

      def prepare
      @base_path     = OT::HOME
      @config_file   = File.join(@base_path, 'etc', 'config.yaml')
      @backup_suffix = Time.now.strftime('%Y%m%d%H%M%S')
      @findings      = []  # Store findings for consolidated output
    end

    def migration_needed?
      unless File.exist?(@config_file)
        error "Config file does not exist: #{@config_file}"
        return false
      end

      scan_for_symbol_keys
    end

    def migrate
      # Print consolidated header
      mode_label = dry_run? ? '(dry-run)' : ''
      info "Symbol Key Migration #{mode_label}".strip
      info "File: #{relative_path(@config_file)}"
      info ''

      # Show what will change
      @findings.each do |finding|
        info "  Line #{finding[:line_num].to_s.rjust(4)}: :#{finding[:key]}: → #{finding[:key]}:"
      end
      info ''

      # Capture count before validation resets @findings
      keys_to_convert = @findings.size

      # Perform migration steps
      backup_path = backup_config
      convert_symbols_to_strings
      success     = validate_conversion

      # Result line
      if success
        if dry_run?
          info "Would convert #{keys_to_convert} key(s) - no changes made"
        else
          info "Converted #{keys_to_convert} key(s)"
          info "Backup: #{relative_path(backup_path)}" if backup_path
        end
      else
        error "Conversion failed - restore from backup: #{relative_path(backup_path)}"
      end

      success
    end

    private

    def relative_path(path)
      path.sub("#{@base_path}/", '')
    end

    def scan_for_symbol_keys
      content = File.read(@config_file)
      lines   = content.lines

      # Check for symbol key patterns:
      # 1. Start of line with optional whitespace, then :key:
      # 2. Array item syntax: - :key:
      symbol_pattern = /^(\s*)(-\s*)?:([a-zA-Z_][a-zA-Z0-9_]*):/

      lines.each_with_index do |line, idx|
        next unless line.match?(symbol_pattern)

        match = line.match(symbol_pattern)
        @findings << {
          line_num: idx + 1,
          key: match[3],
          content: line.chomp,
        }
      end

      @findings.any?
    end

    def backup_config
      backup_path = "#{@config_file}.#{@backup_suffix}-01.bak"

      return backup_path if File.exist?(backup_path)

      for_realsies_this_time? do
        FileUtils.cp(@config_file, backup_path)
        track_stat(:backup_created)
      end

      backup_path
    end

    def convert_symbols_to_strings
      for_realsies_this_time? do
        # Convert YAML symbol keys to string keys using perl
        # Pattern handles:
        #   - Top-level and nested: ^(\s*):key: → \1key:
        #   - Array items: ^(\s*)(-\s*):key: → \1\2key:
        cmd = <<~SHELL
          perl -i -pe 's/^(\\s*)(-\\s*)?:([a-zA-Z_][a-zA-Z0-9_]*)/\\1\\2\\3/g' '#{@config_file}'
        SHELL

        unless system(cmd)
          error 'perl conversion failed'
          return false
        end

        track_stat(:symbols_converted)
        true
      end
    end

    def validate_conversion
      return true if dry_run?

      # Re-scan to check for remaining symbol keys
      @findings = []
      if scan_for_symbol_keys
        error 'Symbol keys still present after conversion'
        return false
      end

      # Verify YAML is still valid
      begin
        YAML.safe_load_file(@config_file, permitted_classes: [Symbol])
        true
      rescue Psych::SyntaxError => ex
        error "YAML syntax error: #{ex.message}"
        false
      end
    end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::ConvertSymbolKeys.cli_run)
end
