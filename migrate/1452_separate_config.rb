#!/usr/bin/env ruby
# migrate/1452_separate_config.rb
#
# Configuration Separation Migration Script
#
# Purpose: Separates monolithic config.example.yaml into static and dynamic configuration files.
# Static config goes to etc/config.yaml, dynamic config gets loaded into V2::MutableSettings.
#
# Usage:
#   ruby migrate/1452_separate_config.rb --dry-run  # Preview changes
#   ruby migrate/1452_separate_config.rb --run      # Execute migration
#
#   bin/ots migrate 1452_separate_config.rb

base_path = File.expand_path File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(base_path, 'lib')

require 'onetime'
require 'onetime/migration'
require 'yaml'
require 'fileutils'

require 'onetime/refinements/indifferent_hash_access'

module Onetime
  class Migration < BaseMigration

    using IndifferentHashAccess

    # Configuration mapping for splitting monolithic config
    CONFIG_MAPPINGS = {
      'static' => [
        { 'from' => 'site.host', 'to' => 'site.host' },
        { 'from' => 'site.ssl', 'to' => 'site.ssl' },
        { 'from' => 'site.secret', 'to' => 'site.secret' },
        { 'from' => 'site.authentication.enabled', 'to' => 'site.authentication.enabled' },
        { 'from' => 'site.authentication.colonels', 'to' => 'site.authentication.colonels' },
        { 'from' => 'site.authenticity', 'to' => 'site.authenticity' },
        { 'from' => 'redis.uri', 'to' => 'storage.db.connection.url' },
        { 'from' => 'redis.dbs', 'to' => 'storage.db.database_mapping' },
        { 'from' => 'emailer', 'to' => 'mail.connection' },
        { 'from' => 'mail.truemail', 'to' => 'mail.validation.defaults' },
        { 'from' => 'logging', 'to' => 'logging' },
        { 'from' => 'diagnostics', 'to' => 'diagnostics' },
        { 'from' => 'internationalization', 'to' => 'i18n' },
        { 'from' => 'development', 'to' => 'development' },
        { 'from' => 'experimental.allow_nil_global_secret', 'to' => 'experimental.allow_nil_global_secret' },
        { 'from' => 'experimental.rotated_secrets', 'to' => 'experimental.rotated_secrets' },
        { 'from' => 'experimental.freeze_app', 'to' => 'experimental.freeze_app' },
        { 'from' => 'experimental.middleware', 'to' => 'site.middleware' },
      ],
      'dynamic' => [
        { 'from' => 'site.interface.ui', 'to' => 'user_interface' },
        { 'from' => 'site.authentication.signup', 'to' => 'user_interface.signup' },
        { 'from' => 'site.authentication.signin', 'to' => 'user_interface.signin' },
        { 'from' => 'site.authentication.verify', 'to' => 'user_interface.autoverify' },
        { 'from' => 'site.interface.api', 'to' => 'api' },
        { 'from' => 'site.secret_options', 'to' => 'secret_options' },
        { 'from' => 'features', 'to' => 'features' },
        { 'from' => 'site.regions', 'to' => 'features.regions' },
        { 'from' => 'site.plans', 'to' => 'features.plans' },
        { 'from' => 'site.domains', 'to' => 'features.domains' },
        { 'from' => 'limits', 'to' => 'limits' },
        { 'from' => 'mail.truemail', 'to' => 'mail.validation.recipients' },
        { 'from' => 'mail.truemail', 'to' => 'mail.validation.accounts' },
      ],
    }.freeze

    def prepare
      info("Preparing migration")
      @base_path = File.expand_path File.join(File.dirname(__FILE__), '..')
      @source_config = File.join(@base_path, 'etc', 'config.yaml')
      @backup_suffix = Time.now.strftime('%Y%m%d%H%M%S')
      @converted_config = File.join(@base_path, 'etc', 'config.converted.yaml')
      @static_config = File.join(@base_path, 'etc', 'config.static.yaml')
      @dynamic_config = File.join(@base_path, 'etc', 'config.dynamic.yaml')
      @final_static_path = File.join(@base_path, 'etc', 'config.yaml')
      @final_dynamic_path = File.join(@base_path, 'etc', 'mutable_settings.yaml')

      debug ''
      debug "Paths:"
      debug "Base path: #{@base_path}"
      debug "Source file: #{@source_config}"
      debug "Dynamic file: #{@final_dynamic_path}"
      debug ''
    end

    def migration_needed?

      unless File.exist?(@source_config)
        raise "Source config file does not exist (#{@source_config})"
      end

      config = YAML.load_file(@source_config)

      if config.nil? || config.empty?
        raise 'Source config file is empty'
      end

      # Check if all static mapping source paths exist with non-nil values
      ret = CONFIG_MAPPINGS['static'].all? do |mapping|
        from_path = mapping['from']
        value = get_nested_value(config, from_path.split('.'))
        info("Checking setting: #{from_path} #{value.class}")
        !value.nil?
      end

      ret
    rescue => e
      error "Error: #{e.message}"
      false
    end

    def migration_not_needed_banner
      # Print help message for things to check to give a clue as to what to do
      # next
      source_file = File.basename(@source_config)
      dynamic_file = File.basename(@final_dynamic_path)

      info <<~HEREDOC

        #{separator}
        Things to try:

          1. Check if migration has already completed.
             If you have etc/#{dynamic_file}
             and etc/#{source_file} is in the new format, the migration
             has already run successfully and you're good to go.

          2. Review the source configuration file.
             Check etc/#{source_file} for any missing or invalid settings.
             In needs to be a working config file.

          3. Look for diagnostic hints.
             Re-run with debug output:

              $ ONETIME_DEBUG=1 bin/ots migrate [--run] 1452_separate_config.rb

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

      info "Starting configuration separation migration"
      info "Source: #{@source_config}"

      # Step 1: Create backup if it doesn't exist
      backup_config

      # Step 2: Convert symbol keys to strings if needed
      convert_symbols_to_strings

      # Step 3: Separate config into static and dynamic parts
      separate_configuration

      # Step 4: Move files to final locations
      finalize_configuration

      print_summary do
        info "Configuration separation completed successfully"
        info "Static config: #{@final_static_path}"
        info "Dynamic config: #{@final_dynamic_path}"
        separator
        info "Files processed: #{@stats[:files_processed]}"
        info "Errors encountered: #{@stats[:errors]}"
      end

      true
    end

    private

    def separator
      '-' * 60
    end

    def get_nested_value(hash, keys)
      keys.reduce(hash) { |h, key| h&.dig(key) }
    end

    def backup_config
      backup_path = "#{@source_config}.#{@backup_suffix}"

      if File.exist?(backup_path)
        info "Backup already exists: #{backup_path}"
        return
      end

      for_realsies? do
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

      for_realsies? do
        # Use perl to convert symbol keys to strings
        cmd = "perl -pe 's/^(\\s*):([a-zA-Z_][a-zA-Z0-9_]*)/\\1\\2/g' '#{@source_config}' > '#{@converted_config}'"
        success = system(cmd)

        unless success
          error "Failed to convert symbol keys to strings"
          return false
        end

        track_stat(:symbols_converted)
        info "Converted symbols to strings: #{@converted_config}"
      end
    end

    def separate_configuration
      return if File.exist?(@static_config) && File.exist?(@dynamic_config)

      for_realsies? do
        generate_static_config_with_yq
        generate_dynamic_config_with_yq
        track_stat(:configs_separated)
      end
    end

    def generate_static_config_with_yq
      info "Creating static configuration with yq (preserving comments)..."

      # Initialize empty config
      system("yq eval 'del(.[])' <<< '{}' > '#{@static_config}'")

      CONFIG_MAPPINGS['static'].each do |mapping|
        from_path = mapping['from']
        to_path = mapping['to']

        generate_yq_command(@static_config, from_path, to_path)
      end

      info "Generated static config: #{@static_config}"
      show_config_structure(@static_config, "Static")
    end

    def generate_dynamic_config_with_yq
      info "Creating dynamic configuration with yq (preserving comments)..."

      # Initialize empty config
      system("yq eval 'del(.[])' <<< '{}' > '#{@dynamic_config}'")

      CONFIG_MAPPINGS['dynamic'].each do |mapping|
        from_path = mapping['from']
        to_path = mapping['to']

        generate_yq_command(@dynamic_config, from_path, to_path)
      end

      info "Generated dynamic config: #{@dynamic_config}"
      show_config_structure(@dynamic_config, "Dynamic")
    end

    def generate_yq_command(output_file, from_path, to_path)
      # Handle wildcard mappings (ending with .)
      if from_path.end_with?('.')
        from_path = from_path.chomp('.')
      end

      # Convert dot notation to yq path notation
      from_yq = convert_to_yq_path(from_path)
      to_yq = convert_to_yq_path(to_path)

      # Generate and execute yq command
      cmd = "yq eval '.#{to_yq} = load(\"#{@converted_config}\").#{from_yq}' -i '#{output_file}'"

      info "  Mapping: #{from_path} -> #{to_path}"

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

    def show_config_structure(config_file, config_type)
      if File.exist?(config_file)
        info "#{config_type} config structure:"
        system("yq eval 'keys' '#{config_file}'")
      end
    end

    def finalize_configuration
      # Move static config to final location (replace existing)
      if File.exist?(@static_config)
        for_realsies? do
          FileUtils.mv(@static_config, @final_static_path)
          track_stat(:static_finalized)
          info "Replaced static config at: #{@final_static_path}"
        end
      end

      # Move dynamic config to final location
      if File.exist?(@dynamic_config)
        # Ensure target directory exists
        FileUtils.mkdir_p(File.dirname(@final_dynamic_path))

        for_realsies? do
          FileUtils.mv(@dynamic_config, @final_dynamic_path)
          track_stat(:dynamic_finalized)
          info "Created dynamic config at: #{@final_dynamic_path}"
        end
      end

      # Clean up temporary files in actual run
      for_realsies? do
        cleanup_temp_files
      end
    end

    def cleanup_temp_files
      [@converted_config, @static_config, @dynamic_config].each do |file|
        if File.exist?(file)
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
