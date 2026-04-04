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

# Conditionally load plugin initializers based on feature configuration.
#
# Only requiring files when the plugin is enabled ensures that
# defined?(Billing) returns nil when billing is disabled, and
# defined?(Auth) returns nil when auth mode is not 'full'.
#
# This pattern supports future plugins (SSO providers, mail providers, etc.)
# by making module existence a reliable feature detection mechanism.

if Onetime.auth_config.full_enabled?
  Dir[File.expand_path('../../apps/web/auth/initializers/*.rb', __dir__)].each do |file|
    require file
  end
end

if Onetime.billing_config.enabled?
  Dir[File.expand_path('../../apps/web/billing/initializers/*.rb', __dir__)].each do |file|
    require file
  end
end
