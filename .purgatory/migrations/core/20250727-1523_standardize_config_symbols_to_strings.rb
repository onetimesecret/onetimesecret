#!/usr/bin/env ruby
#
# frozen_string_literal: true

# migrate/20250727-1523_standardize_config_symbols_to_strings.rb
#
# Configuration Standardization Migration
#
# Symbols vs Strings: the old config file used symbols for keys, while the new config file uses
# strings.
#
# **NOTE**: The reason we use `yq` even though it adds a system dependency is that
# it can transform YAML _with_ comments and preserve their structure.
#
# Usage:
#   ruby migrate/20250727-1523_standardize_config_symbols_to_strings.rb --dry-run  # Preview changes
#   ruby migrate/20250727-1523_standardize_config_symbols_to_strings.rb --run      # Execute migration
#
#   bin/ots migrate 20250731-1523_standardize_config_symbols_to_strings.rb

BASE_PATH = File.expand_path File.join(File.dirname(__FILE__), '..', '..')
$:.unshift File.join(BASE_PATH, 'lib')

require 'onetime'
require 'onetime/migration'
require 'yaml'
require 'fileutils'

module Onetime
  class Migration < BaseMigration
    # Configuration mapping for splitting monolithic config
    CONFIG_MAPPINGS = {
      'static' => [
        { 'from' => 'site', 'to' => 'site' },
        { 'from' => 'features', 'to' => 'features' },
        { 'from' => 'redis', 'to' => 'redis' },
        { 'from' => 'logging', 'to' => 'logging' },
        { 'from' => 'emailer', 'to' => 'emailer' },
        { 'from' => 'billing', 'to' => 'billing', 'default' => {} },
        { 'from' => 'mail', 'to' => 'mail' },
        { 'from' => 'internationalization', 'to' => 'internationalization' },
        { 'from' => 'diagnostics', 'to' => 'diagnostics' },
        { 'from' => 'development', 'to' => 'development' },
        { 'from' => 'experimental', 'to' => 'experimental' },
      ],
    }.freeze

    def prepare
      info('Preparing migration')
      @base_path         = BASE_PATH
      @source_config     = File.join(@base_path, 'etc', 'config.yaml')
      @backup_suffix     = Time.now.strftime('%Y%m%d%H%M%S')
      @converted_config  = File.join(@base_path, 'etc', 'config.converted.yaml')
      @static_config     = File.join(@base_path, 'etc', 'config.static.yaml')
      @final_static_path = File.join(@base_path, 'etc', 'config.yaml')

      debug ''
      debug 'Paths:'
      debug "Base path: #{@base_path}"
      debug "Source file: #{@source_config}"
      debug ''
    end

    def migration_needed?
      unless File.exist?(@source_config)
        raise "Source config file does not exist (#{@source_config})"
      end

      # The "old" config file that we are migrating from already has symbolized
      # keys in the actual file, so in order to load it safely we need to
      # explicitly permit Symbols.
      config = YAML.safe_load_file(@source_config, permitted_classes: [Symbol])

      if config.nil? || config.empty?
        raise 'Source config file is empty'
      end

      # Check if all static mapping source paths exist with non-nil values
      CONFIG_MAPPINGS['static'].all? do |mapping|
        from_path     = mapping['from']
        default_value = mapping.fetch('default', nil)
        value         = get_nested_value(config, from_path.split('.'))
        info("Checking setting (is nil: #{value.nil?}): #{from_path} #{value.class}")
        # If there is a value or a default value, all is good
        !value.nil? || !default_value.nil?
      end
    rescue StandardError => ex
      error "Error: #{ex.message}"
      false
    end

    def migration_not_needed_banner
      # Print help message for things to check to give a clue as to what to do
      # next
      source_file = File.basename(@source_config)

      info <<~HEREDOC

        #{separator}
        Things to try:

          1. Check if migration has already completed.
             If you have etc/#{source_file} and the keys are strings, the migration
             has already run successfully and you're good to go.

          2. Review the source configuration file.
             Check etc/#{source_file} for any missing or invalid settings.
             In needs to be a working config file.

          3. Look for diagnostic hints.
             Re-run with debug output:

              $ ONETIME_DEBUG=1 bin/ots migrate [--run] 20250731-1523_standardize_config_symbols_to_strings.rb

          4. Try running with the default config.
             Copy etc/defaults/config.defaults.yaml to etc/#{source_file} and
             try to run the application:

              $ bin/ots console

             If the console starts and boots successfully, you will need to
             manually copy over your settings from your original etc/config.yaml.

        #{separator}
      HEREDOC
    end

    def migrate
      run_mode_banner

      # Validate source file exists
      unless File.exist?(@source_config)
        error "Source config file not found: #{@source_config}"
        return false
      end

      info 'Starting configuration separation migration'
      info "Source: #{@source_config}"
      debug 'Source config top-level keys:'
      system("yq eval 'keys' '#{@source_config}'")
      debug ''

      # Step 1: Create backup if it doesn't exist
      backup_config

      # Step 2: Convert symbol keys to strings if needed
      convert_symbols_to_strings

      # Step 3: Separate config into static and mutable parts
      separate_configuration

      # Step 4: Move files to final locations
      finalize_configuration

      print_summary do
        info ''
        info 'Configuration standardization completed successfully'
        info "Static config: #{@final_static_path}"
        info ''
      end

      true
    end

    private

    def get_nested_value(hash, keys)
      keys.reduce(hash) { |h, key| h&.dig(key.to_sym) }
    end

    def backup_config
      backup_path = "#{@source_config}.#{@backup_suffix}"

      if File.exist?(backup_path)
        info "Backup already exists: #{backup_path}"
        return
      end

      for_realsies_this_time? do
        FileUtils.cp(@source_config, backup_path)
        track_stat(:backup_created)
        info "Created backup: #{backup_path}"
      end
    end

    def convert_symbols_to_strings
      if File.exist?(@converted_config)
        info "Converted config already exists: #{@converted_config}"
        return
      end

      for_realsies_this_time? do
        # Convert YAML symbol keys (like :key: and - :key:) to string keys (like key: and - key:)
        cmd = "perl -pe 's/^(\\s*)(-\\s*)?:([a-zA-Z_][a-zA-Z0-9_]*)/\\1\\2\\3/g' '#{@source_config}' > '#{@converted_config}'"

        success = system(cmd)

        unless success
          error 'Failed to convert symbol keys to strings'
          return false
        end

        track_stat(:symbols_converted)
        info "Converted symbols to strings: #{@converted_config}"

        # Validate the conversion worked
        unless validate_conversion
          error 'Symbol to string conversion failed validation'
          return false
        end
      end
    end

    def validate_conversion
      return true unless File.exist?(@converted_config)

      info 'Validating symbol to string conversion...'

      # Check for remaining symbol keys in the file (both top-level and array items)
      remaining_symbols  = `grep -n "^[[:space:]]*:[a-zA-Z_][a-zA-Z0-9_]*:" '#{@converted_config}'`
      remaining_symbols += `grep -n "^[[:space:]]*-[[:space:]]*:[a-zA-Z_][a-zA-Z0-9_]*:" '#{@converted_config}'`

      if remaining_symbols.strip.empty?
        info '✓ No symbol keys found - conversion successful'
        true
      else
        error '✗ Found remaining symbol keys:'
        puts remaining_symbols

        # Try to load and show structure
        begin
          config = YAML.safe_load_file(@converted_config)
          info "Converted config top-level keys: #{config.keys.join(', ')}"
        rescue StandardError => ex
          error "Failed to parse converted config: #{ex.message}"
        end

        false
      end
    end

    def separate_configuration
      return if File.exist?(@static_config)

      for_realsies_this_time? do
        generate_static_config_with_yq
        track_stat(:configs_standardized)
      end
    end

    def generate_static_config_with_yq
      info 'Creating static configuration with yq (preserving comments)...'

      # Initialize empty config
      system("yq eval 'del(.[])' <<< '{}' > '#{@static_config}'")

      CONFIG_MAPPINGS['static'].each do |mapping|
        generate_yq_command(@static_config, mapping)
      end

      info "Generated static config: #{@static_config}"
      show_config_structure(@static_config, 'Static')
    end

    def generate_yq_command(output_file, mapping)
      from_path     = mapping['from']
      to_path       = mapping['to']
      default_value = mapping['default']

      # Handle wildcard mappings (ending with .)
      if from_path.end_with?('.')
        from_path = from_path.chomp('.')
      end

      # Convert dot notation to yq path notation
      from_yq = convert_to_yq_path(from_path)
      to_yq   = convert_to_yq_path(to_path)

      # Generate yq command with optional default value
      if default_value.nil?
        # No default - use original behavior
        cmd = "yq eval '.#{to_yq} = load(\"#{@converted_config}\").#{from_yq}' -i '#{output_file}'"
      else
        # Use default value as fallback
        formatted_default = format_default_for_yq(default_value)
        cmd               = "yq eval '.#{to_yq} = (load(\"#{@converted_config}\").#{from_yq} // #{formatted_default})' -i '#{output_file}'"
      end

      info "  Mapping: #{from_path} -> #{to_path}" + (default_value.nil? ? '' : " (default: #{default_value})")

      # Execute the command
      success = system(cmd)
      unless success
        info "    Warning: Failed to map #{from_path} -> #{to_path}"
      end

      success
    end

    def convert_to_yq_path(path)
      # yq uses dot notation, but we need to handle array indices and special characters
      # For now, keeping it simple since the paths in the mapping are already dot notation
      path
    end

    def format_default_for_yq(value)
      case value
      when String
        "\"#{value.gsub('\\', '\\\\').gsub('"', '\\"')}\""
      when TrueClass, FalseClass
        value.to_s
      when Numeric
        value.to_s
      when NilClass
        'null'
      when Array, Hash
        value.to_json
      else
        "\"#{value}\""
      end
    end

    def show_config_structure(config_file, config_type)
      if File.exist?(config_file)
        info "#{config_type} config structure:"
        system("yq eval 'keys' '#{config_file}'")
      end
    end

    def finalize_configuration
      # Move static config to final location (replace existing)
      if File.exist?(@static_config)
        for_realsies_this_time? do
          FileUtils.mv(@static_config, @final_static_path)
          track_stat(:static_finalized)
          info "Replaced static config at: #{@final_static_path}"
        end
      end

      # Clean up temporary files in actual run
      for_realsies_this_time? do
        cleanup_temp_files
      end
    end

    def cleanup_temp_files
      [@converted_config, @static_config].each do |file|
        if file && File.exist?(file)
          FileUtils.rm(file)
          debug "Cleaned up: #{file}"
        end
      end
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
