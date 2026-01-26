# migrations/pending/20250727-1523_02_big_reorganize_config_structure.rb
#
# frozen_string_literal: true

# DEPRECATED: REFERENCE ONLY - DO NOT EXECUTE
# Use the 2026-01-26 migration scripts instead.
#
# ---
#
# Migration 2 of 2: Reorganize Config Structure
#
# This migration reorganizes the config.yaml hierarchy, moving settings
# to their new locations. It expects string keys (run migration 01 first
# if you have symbol keys).
#
# **NOTE**: Uses `yq` to transform YAML while preserving comments.
# Install with: brew install yq (macOS) or apt install yq (Ubuntu)
#
# Usage:
#   bin/ots migrate 20250727-1523_02_reorganize_config_structure.rb           # Preview changes
#   bin/ots migrate --run 20250727-1523_02_reorganize_config_structure.rb     # Execute migration
#
# What it does:
#   1. Creates a timestamped backup of etc/config.yaml
#   2. Creates a new config file with reorganized hierarchy
#   3. Replaces the original with the reorganized version

require 'onetime/migration'
require 'yaml'
require 'fileutils'
require 'json'
require 'shellwords'

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

      # Adding to site
      { 'from' => 'site.ssl', 'to' => 'site.session.secure' },
      { 'from' => 'site.secret', 'to' => 'site.session.secret' },
      { 'from' => 'experimental.middleware', 'to' => 'site.middleware', 'default' => { 'static_files' => true, 'utf8_sanitizer' => true } },

      # Interface moves out of site
      { 'from' => 'site.interface.ui.enabled', 'to' => 'interface.ui.enabled' },
      { 'from' => 'site.interface.ui.header', 'to' => 'interface.ui.page_header' },
      { 'from' => 'site.interface.ui.footer_links', 'to' => 'interface.ui.page_footer.links' },
      { 'from' => 'site.interface.api', 'to' => 'interface.api' },
      { 'from' => 'site.support', 'to' => 'interface.support' },

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
      { 'from' => 'limits', 'to' => 'deprecated.limits' },
      { 'from' => 'logging', 'to' => 'deprecated.logging' },
      { 'from' => 'internationalization', 'to' => 'i18n' },
      { 'from' => 'diagnostics', 'to' => 'diagnostics' },
      { 'from' => 'development', 'to' => 'dev' },

      # Experimental settings
      { 'from' => 'experimental.allow_nil_global_secret', 'to' => 'deprecated.allow_nil_global_secret', 'default' => false },
      { 'from' => 'experimental.rotated_secrets', 'to' => 'deprecated.rotated_secrets', 'default' => [] },
      { 'from' => 'experimental.freeze_app', 'to' => 'deprecated.freeze_app', 'default' => false },

    ].freeze

    def prepare
      @base_path               = OT::HOME
      @source_config           = File.join(@base_path, 'etc', 'config.yaml')
      @backup_suffix           = Time.now.strftime('%Y%m%d%H%M%S')
      @temp_config             = File.join(@base_path, 'etc', 'config.reorganized.yaml')
      @old_keys_found          = []  # Store detected old structure
      @blocked_by_prerequisite = false
    end

    def migration_needed?
      unless File.exist?(@source_config)
        error "Config file does not exist: #{relative_path(@source_config)}"
        @blocked_by_prerequisite = true
        return false
      end

      # Check for symbol keys first - if found, migration 01 needs to run first
      if has_symbol_keys?
        @blocked_by_prerequisite = true
        error 'Prerequisite not met: config still has symbol keys'
        error 'Run migration 01 first:'
        error '  bin/ots migrate --run 20250727-1523_01_convert_symbol_keys.rb'
        return false
      end

      # Check if reorganization is needed by looking for old paths
      needs_reorganization?
    end

    def handle_migration_not_needed
      return nil if @blocked_by_prerequisite  # Error already printed

      info 'Config already in new structure - no changes needed'
      nil
    end

    def migrate
      unless File.exist?(@source_config)
        error "Config file not found: #{relative_path(@source_config)}"
        return false
      end

      # Verify yq is available
      unless system('which yq > /dev/null 2>&1')
        error 'yq is required but not installed.'
        error 'Install with: brew install yq (macOS) or apt install yq (Ubuntu)'
        return false
      end

      # Print consolidated header
      mode_label = dry_run? ? '(dry-run)' : ''
      info "Config Structure Migration #{mode_label}".strip
      info "File: #{relative_path(@source_config)}"
      info ''

      # Show what triggered the migration
      info 'Old structure detected:'
      @old_keys_found.each { |key| info "  - #{key}" }
      info ''

      # Perform migration steps
      backup_path    = backup_config
      generate_reorganized_config
      finalize_config

      # Result line
      if dry_run?
        info "Would apply #{CONFIG_MAPPINGS.size} mappings - no changes made"
      else
        info "Applied #{CONFIG_MAPPINGS.size} mappings"
        info "Backup: #{relative_path(backup_path)}" if backup_path
      end

      true
    end

    private

    def relative_path(path)
      path.sub("#{@base_path}/", '')
    end

    def has_symbol_keys?
      content = File.read(@source_config)
      content.match?(/^(\s*)(-\s*)?:([a-zA-Z_][a-zA-Z0-9_]*):/)
    end

    def needs_reorganization?
        config = YAML.safe_load_file(@source_config, permitted_classes: [Symbol])

        # Detect old structure markers
        @old_keys_found << 'redis' if config.key?('redis')
        @old_keys_found << 'emailer' if config.key?('emailer')
        @old_keys_found << 'internationalization' if config.key?('internationalization')
        @old_keys_found << 'site.interface' if config.dig('site', 'interface') && !config.key?('interface')

        @old_keys_found.any?
    rescue StandardError => ex
        error "Failed to parse config: #{ex.message}"
        false
    end

    def backup_config
      backup_path = "#{@source_config}.#{@backup_suffix}-02.bak"

      return backup_path if File.exist?(backup_path)

      for_realsies_this_time? do
        FileUtils.cp(@source_config, backup_path)
        track_stat(:backup_created)
      end

      backup_path
    end

    def generate_reorganized_config
      for_realsies_this_time? do
        # Initialize empty config file
        system("echo '---' > '#{@temp_config}'")

        # Apply each mapping silently
        CONFIG_MAPPINGS.each do |mapping|
          apply_mapping(mapping)
        end

        track_stat(:mappings_applied, CONFIG_MAPPINGS.size)
      end
    end

    def apply_mapping(mapping)
      from_path     = mapping['from']
      to_path       = mapping['to']
      default_value = mapping['default']

      # Skip 'doesnotexist' paths - these are just for setting defaults
      if from_path == 'doesnotexist'
        apply_default_value(to_path, default_value) if default_value
        return
      end

      # Build yq command
      if default_value.nil?
        cmd = "yq eval '.#{to_path} = load(\"#{@source_config}\").#{from_path}' -i '#{@temp_config}'"
      else
        formatted_default = format_for_yq(default_value)
        cmd               = "yq eval '.#{to_path} = (load(\"#{@source_config}\").#{from_path} // #{formatted_default})' -i '#{@temp_config}'"
      end

      system(cmd)
    end

    def apply_default_value(to_path, default_value)
      formatted_default = format_for_yq(default_value)
      cmd               = "yq eval '.#{to_path} = #{formatted_default}' -i '#{@temp_config}'"
      system(cmd)
    end

    def format_for_yq(value)
      case value
      when String
        escape_for_yq(value)
      when TrueClass, FalseClass
        value.to_s
      when Numeric
        value.to_s
      when NilClass
        'null'
      when Array, Hash
        value.to_json
      else
        escape_for_yq(value.to_s)
      end
    end

    # Properly escape a string for use in yq commands embedded in shell
    #
    # Uses Shellwords.escape (Ruby stdlib) to handle all shell metacharacters
    # including command substitution ($(), ``), quotes, and special characters.
    #
    # For yq string values, we first create a quoted YAML string expression,
    # then shell-escape the entire thing to prevent injection.
    #
    def escape_for_yq(str)
      # Create a properly quoted YAML string (yq expects "quoted" for strings)
      # Escape internal backslashes and double quotes for YAML
      yaml_string = "\"#{str.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}\""

      # Shell-escape the entire quoted string to prevent command injection
      Shellwords.escape(yaml_string)
    end

    def finalize_config
      return unless File.exist?(@temp_config)

      for_realsies_this_time? do
        FileUtils.mv(@temp_config, @source_config)
        track_stat(:config_finalized)
      end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.cli_run)
end
