# lib/onetime/application.rb

# Character Encoding Configuration
# Set UTF-8 as the default external encoding to ensure consistent text handling:
# - Standardizes file and network I/O operations
# - Normalizes STDIN/STDOUT/STDERR encoding
# - Provides default encoding for strings from external sources
# This prevents encoding-related bugs, especially on fresh OS installations
# where locale settings may not be properly configured.
Encoding.default_external = Encoding::UTF_8

require_relative 'application/base'
require_relative 'application/registry'
require_relative 'application/auth_strategies'
require_relative 'application/middleware_stack'

module Onetime
  # Application Framework
  #
  # Provides base classes and utilities for building modular Rack applications
  module Application
  end
end
