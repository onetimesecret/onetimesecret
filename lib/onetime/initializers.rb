# lib/onetime/initializers.rb
#
# frozen_string_literal: true

require_relative 'initializers/set_secrets'
require_relative 'initializers/load_locales'
require_relative 'initializers/setup_database_logging'
require_relative 'initializers/detect_legacy_data_and_warn'
require_relative 'initializers/configure_familia'
require_relative 'initializers/setup_connection_pool'
require_relative 'initializers/load_fortunes'
require_relative 'initializers/check_global_banner'
require_relative 'initializers/configure_truemail'
require_relative 'initializers/configure_domains'
require_relative 'initializers/configure_rhales'
require_relative 'initializers/setup_loggers'
require_relative 'initializers/setup_diagnostics'
require_relative 'initializers/print_log_banner'
