# migrations/20250727-1523_02_reorganize_config_hierarchy.rb
#
# frozen_string_literal: true

# Migration 2 of 2: Reorganize Config Hierarchy
#
# This migration reorganizes the config.yaml hierarchy, moving settings
# to their new locations. It expects string keys (run migration 01 first
# if you have symbol keys).
#
# **NOTE**: Uses `yq` to transform YAML while preserving comments.
# Install with: brew install yq (macOS) or apt install yq (Ubuntu)
#
# Usage:
#   ruby migrations/20250727-1523_02_reorganize_config_hierarchy.rb --dry-run
#   ruby migrations/20250727-1523_02_reorganize_config_hierarchy.rb --run
#
# What it does:
#   1. Creates a timestamped backup of etc/config.yaml
#   2. Creates a new config file with reorganized hierarchy
#   3. Replaces the original with the reorganized version

BASE_PATH = File.expand_path File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(BASE_PATH, 'lib')

require 'onetime'
require 'onetime/migration'
require 'yaml'
require 'fileutils'
require 'json'

module Onetime
  class Migration < BaseMigration
    # Configuration mapping: 'from' path in old config → 'to' path in new config
    # If 'default' is provided, it's used when the source path doesn't exist
    CONFIG_MAPPINGS = [
      # Site settings (mostly staying in place)
      { 'from' => 'site.host', 'to' => 'site.host' },
      { 'from' => 'site.ssl', 'to' => 'site.ssl' },
      { 'from' => 'site.secret', 'to' => 'site.secret' },
      { 'from' => 'site.authenticity', 'to' => 'site.authenticity' },

      # Session config (new section)
      { 'from' => 'doesnotexist', 'to' => 'site.session', 'default' => {} },

      # Interface moves out of site
      { 'from' => 'site.interface', 'to' => 'interface' },

      # Features consolidation
      { 'from' => 'features', 'to' => 'features', 'default' => {} },
      { 'from' => 'site.secret_options', 'to' => 'features.secret_links.privacy_options' },
      { 'from' => 'site.regions', 'to' => 'features.regions', 'default' => { 'enabled' => false } },
      { 'from' => 'site.domains', 'to' => 'features.domains', 'default' => { 'enabled' => false } },
      { 'from' => 'features.incoming', 'to' => 'features.incoming', 'default' => { 'enabled' => false } },

      # Redis → Database
      { 'from' => 'redis.uri', 'to' => 'database.url' },
      { 'from' => 'redis.dbs', 'to' => 'database.model_mapping' },

      # Mail consolidation
      { 'from' => 'emailer', 'to' => 'mail.connection' },
      { 'from' => 'mail.truemail', 'to' => 'mail.validation.defaults' },
      { 'from' => 'doesnotexist', 'to' => 'mail.validation.recipients', 'default' => {} },
      { 'from' => 'doesnotexist', 'to' => 'mail.validation.accounts', 'default' => {} },

      # Top-level sections (kept as-is)
      { 'from' => 'limits', 'to' => 'limits' },
      { 'from' => 'logging', 'to' => 'logging' },
      { 'from' => 'internationalization', 'to' => 'i18n' },
      { 'from' => 'diagnostics', 'to' => 'diagnostics' },
      { 'from' => 'development', 'to' => 'development' },

      # Experimental settings
      { 'from' => 'experimental.allow_nil_global_secret', 'to' => 'experimental.allow_nil_global_secret', 'default' => false },
      { 'from' => 'experimental.rotated_secrets', 'to' => 'experimental.rotated_secrets', 'default' => [] },
      { 'from' => 'experimental.freeze_app', 'to' => 'experimental.freeze_app', 'default' => false },
      { 'from' => 'experimental.middleware', 'to' => 'site.middleware', 'default' => { 'static_files' => true, 'utf8_sanitizer' => true } },
    ].freeze

    def prepare
      info('Preparing config hierarchy reorganization')
      @base_path = BASE_PATH
      @source_config = File.join(@base_path, 'etc', 'config.yaml')
      @backup_suffix = Time.now.strftime('%Y%m%d%H%M%S')
      @temp_config = File.join(@base_path, 'etc', 'config.reorganized.yaml')

      debug ''
      debug 'Paths:'
      debug "  Base path: #{@base_path}"
      debug "  Source config: #{@source_config}"
      debug "  Temp config: #{@temp_config}"
      debug ''
    end

    def migration_needed?
      unless File.exist?(@source_config)
        error "Source config file does not exist: #{@source_config}"
        return false
      end

      # Check for symbol keys first - if found, migration 01 needs to run first
      if has_symbol_keys?
        error 'Config file still has symbol keys. Run migration 01 first:'
        error '  ruby migrations/20250727-1523_01_convert_symbol_keys.rb --run'
        return false
      end

      # Check if reorganization is needed by looking for old paths
      needs_reorganization?
    end

    def migrate
      run_mode_banner

      unless File.exist?(@source_config)
        error "Source config file not found: #{@source_config}"
        return false
      end

      # Verify yq is available
      unless system('which yq > /dev/null 2>&1')
        error 'yq is required but not installed.'
        error 'Install with: brew install yq (macOS) or apt install yq (Ubuntu)'
        return false
      end

      info 'Starting config hierarchy reorganization'
      info "Source: #{@source_config}"
      debug ''

      # Show current structure
      debug 'Current top-level keys:'
      system("yq eval 'keys' '#{@source_config}'")
      debug ''

      # Step 1: Create backup
      backup_config

      # Step 2: Generate reorganized config
      generate_reorganized_config

      # Step 3: Replace original with reorganized
      finalize_config

      print_summary do
        info ''
        info 'Config hierarchy reorganization completed successfully'
        info "Config file: #{@source_config}"
        info ''
        info 'New top-level keys:'
        system("yq eval 'keys' '#{@source_config}'") if actual_run?
        info ''
      end

      true
    end

    private

    def has_symbol_keys?
      content = File.read(@source_config)
      content.match?(/^(\s*)(-\s*)?:([a-zA-Z_][a-zA-Z0-9_]*):/)
    end

    def needs_reorganization?
      begin
        config = YAML.safe_load_file(@source_config)

        # Check if old structure exists (redis, emailer, internationalization)
        old_paths_exist = config.key?('redis') ||
                          config.key?('emailer') ||
                          config.key?('internationalization') ||
                          (config.dig('site', 'interface') && !config.key?('interface'))

        if old_paths_exist
          info 'Old config structure detected - reorganization needed'
          debug '  Found: redis' if config.key?('redis')
          debug '  Found: emailer' if config.key?('emailer')
          debug '  Found: internationalization' if config.key?('internationalization')
          debug '  Found: site.interface (should be top-level interface)' if config.dig('site', 'interface')
          true
        else
          info 'Config already appears to be in new structure'
          false
        end
      rescue StandardError => e
        error "Failed to parse config: #{e.message}"
        false
      end
    end

    def backup_config
      backup_path = "#{@source_config}.#{@backup_suffix}.bak"

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

    def generate_reorganized_config
      for_realsies_this_time? do
        info 'Creating reorganized configuration with yq...'

        # Initialize empty config file
        system("echo '---' > '#{@temp_config}'")

        # Apply each mapping
        CONFIG_MAPPINGS.each do |mapping|
          apply_mapping(mapping)
        end

        track_stat(:mappings_applied, CONFIG_MAPPINGS.size)
        info "Generated reorganized config: #{@temp_config}"

        # Show new structure
        debug ''
        debug 'New config structure:'
        system("yq eval 'keys' '#{@temp_config}'")
      end
    end

    def apply_mapping(mapping)
      from_path = mapping['from']
      to_path = mapping['to']
      default_value = mapping['default']

      # Skip 'doesnotexist' paths - these are just for setting defaults
      if from_path == 'doesnotexist'
        if default_value
          apply_default_value(to_path, default_value)
        end
        return
      end

      # Convert dot notation to yq path
      from_yq = from_path
      to_yq = to_path

      # Build yq command
      if default_value.nil?
        # No default - copy value or null
        cmd = "yq eval '.#{to_yq} = load(\"#{@source_config}\").#{from_yq}' -i '#{@temp_config}'"
      else
        # With default fallback
        formatted_default = format_for_yq(default_value)
        cmd = "yq eval '.#{to_yq} = (load(\"#{@source_config}\").#{from_yq} // #{formatted_default})' -i '#{@temp_config}'"
      end

      info "  #{from_path} → #{to_path}" + (default_value ? " (default: #{default_value.inspect})" : '')

      success = system(cmd)
      unless success
        warn "    Warning: Failed to map #{from_path} → #{to_path}"
      end
    end

    def apply_default_value(to_path, default_value)
      formatted_default = format_for_yq(default_value)
      cmd = "yq eval '.#{to_path} = #{formatted_default}' -i '#{@temp_config}'"

      info "  (new) → #{to_path} (default: #{default_value.inspect})"

      success = system(cmd)
      unless success
        warn "    Warning: Failed to set default for #{to_path}"
      end
    end

    def format_for_yq(value)
      case value
      when String
        "\"#{value.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}\""
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

    def finalize_config
      return unless File.exist?(@temp_config)

      for_realsies_this_time? do
        FileUtils.mv(@temp_config, @source_config)
        track_stat(:config_finalized)
        info "Replaced config with reorganized version"
      end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
