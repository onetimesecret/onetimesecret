# lib/onetime/boot/core_initializers.rb
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
require_relative 'initializer_registry'

# Core initializers (no dependencies)
require_relative 'initializers/load_locales'
require_relative 'initializers/setup_loggers'
require_relative 'initializers/set_secrets'
require_relative 'initializers/configure_domains'
require_relative 'initializers/configure_truemail'
require_relative 'initializers/configure_rhales'
require_relative 'initializers/load_fortunes'

# Dependent initializers
require_relative 'initializers/setup_diagnostics'      # depends_on: [:logging]
require_relative 'initializers/setup_database_logging' # depends_on: [:logging]
require_relative 'initializers/configure_familia'      # depends_on: [:logging]
require_relative 'initializers/detect_legacy_data_and_warn' # depends_on: [:familia_config]
require_relative 'initializers/setup_connection_pool'  # depends_on: [:legacy_check]
require_relative 'initializers/check_global_banner'    # depends_on: [:database]
require_relative 'initializers/print_log_banner'       # depends_on: [:logging]
