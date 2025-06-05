# lib/onetime/initializers.rb

require_relative 'initializers/set_global_secret'   # TODO: Combine into
require_relative 'initializers/set_rotated_secrets' # set_secrets
require_relative 'initializers/load_locales'
require_relative 'initializers/connect_databases'
require_relative 'initializers/prepare_emailers'
require_relative 'initializers/load_fortunes'
require_relative 'initializers/check_global_banner'
require_relative 'initializers/load_plans'
require_relative 'initializers/configure_truemail'
require_relative 'initializers/configure_domains'
require_relative 'initializers/setup_authentication'
require_relative 'initializers/setup_diagnostics'
require_relative 'initializers/setup_system_settings'
require_relative 'initializers/print_log_banner'
