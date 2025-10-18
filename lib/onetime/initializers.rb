# lib/onetime/initializers.rb

require_relative 'initializers/set_global_secret'   # TODO: Combine into
require_relative 'initializers/set_rotated_secrets' # set_secrets
require_relative 'initializers/load_locales'
require_relative 'initializers/setup_database_logging'
require_relative 'initializers/connect_databases'
require_relative 'initializers/load_fortunes'
require_relative 'initializers/check_global_banner'
require_relative 'initializers/configure_truemail'
require_relative 'initializers/configure_domains'
require_relative 'initializers/configure_rhales'
require_relative 'initializers/setup_diagnostics'
require_relative 'initializers/detect_legacy_data_and_warn'
require_relative 'initializers/print_log_banner'
