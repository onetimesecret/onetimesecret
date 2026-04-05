# lib/onetime/initializers.rb
#
# frozen_string_literal: true

# Load core boot initializers
#
# These are system-level initializers that set up the fundamental
# infrastructure (logging, config, database) required by the application.
#
# Each initializer is a class that auto-registers via inherited hook.
# Dependencies are declared via class instance variables.

# Load the initializer base class and registry first
require_relative 'boot/initializer_registry'

# Core initializers (no dependencies)
require_relative 'initializers/load_locales'
require_relative 'initializers/setup_i18n'        # requires: [:i18n]
require_relative 'initializers/setup_loggers'
require_relative 'initializers/set_secrets'
require_relative 'initializers/configure_domains'
require_relative 'initializers/configure_truemail'
require_relative 'initializers/configure_rhales'
require_relative 'initializers/load_fortunes'

# Dependent initializers
require_relative 'initializers/setup_diagnostics'      # depends_on: [:logging]
require_relative 'initializers/setup_database_logging' # depends_on: [:logging]
require_relative 'initializers/setup_auth_database'    # depends_on: [:logging], fork-sensitive
require_relative 'initializers/setup_rabbitmq'         # depends_on: [:logging]
require_relative 'initializers/configure_familia'      # depends_on: [:logging]
require_relative 'initializers/detect_legacy_data_and_warn' # depends_on: [:familia_config]
require_relative 'initializers/setup_connection_pool'  # depends_on: [:legacy_check]
require_relative 'initializers/check_global_banner'    # depends_on: [:database]
require_relative 'initializers/print_log_banner'       # depends_on: [:logging]

# Convention-based plugin discovery and initialization.
#
# Plugin Convention:
#   1. Plugin directory: apps/web/<plugin_name>/ or apps/api/<plugin_name>/
#   2. Config singleton: Onetime.<plugin_name>_config (responds to enabled? or full_enabled?)
#   3. Initializers: apps/{web,api}/<plugin_name>/initializers/*.rb
#
# Adding a new plugin requires NO changes to this file. Simply:
#   - Create apps/{web,api}/<plugin_name>/initializers/ directory
#   - Define Onetime.<plugin_name>_config singleton with enabled? method
#
# Plugins without a config singleton are always loaded (their initializers
# use should_skip? internally to decide whether to run).
#
# Only requiring files when the plugin is enabled ensures that
# defined?(Billing) returns nil when billing is disabled, and
# defined?(Auth) returns nil when auth mode is not 'full'.
# This makes module existence a reliable feature detection mechanism.

# Directories that are not plugins (e.g., shared code)
PLUGIN_SKIP_LIST = %w[core].freeze

# Discover plugin directories under apps/web/ and apps/api/
apps_base   = File.expand_path('../../apps', __dir__)
plugin_dirs = Dir[File.join(apps_base, '{web,api}', '*/')]

plugin_dirs.each do |plugin_dir|
  plugin_name = File.basename(plugin_dir)

  # Skip non-plugin directories
  next if PLUGIN_SKIP_LIST.include?(plugin_name)

  # Check for <plugin>_config singleton with enabled? method
  config_method = "#{plugin_name}_config"
  has_config    = Onetime.respond_to?(config_method)

  if has_config
    config = Onetime.public_send(config_method)

    # Support both enabled? and full_enabled? (auth uses full_enabled?)
    enabled = if config.respond_to?(:full_enabled?)
                config.full_enabled?
              elsif config.respond_to?(:enabled?)
                config.enabled?
              else
                false
              end

    next unless enabled
  end
  # No config singleton = always load (initializers handle their own skip logic)

  # Load initializers for plugin (sorted for deterministic order)
  initializers_pattern = File.join(plugin_dir, 'initializers', '*.rb')
  initializer_files    = Dir[initializers_pattern]

  next if initializer_files.empty?

  OT.ld "[initializers] Loading #{plugin_name} plugin (#{initializer_files.size} initializers)"

  initializer_files.each do |file|
    require file
  end
end
