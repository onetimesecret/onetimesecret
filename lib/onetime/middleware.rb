# lib/onetime/middleware.rb

require 'logger'
require_relative '../middleware/handle_invalid_percent_encoding'
require_relative '../middleware/handle_invalid_utf8'
require_relative '../middleware/detect_host'
require_relative 'middleware/domain_strategy'
require_relative 'middleware/identity_resolution'
require_relative 'middleware/startup_readiness'
require_relative 'middleware/security'
require_relative 'middleware/static_files'
