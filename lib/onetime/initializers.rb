# lib/onetime/initializers.rb

require_relative 'initializers/boot'
require_relative 'initializers/set_global_secret'
require_relative 'initializers/load_locales'
require_relative 'initializers/connect_databases'
require_relative 'initializers/prepare_emailers'
