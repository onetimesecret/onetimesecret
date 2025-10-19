# apps/web/auth/config/hooks.rb

require_relative 'hooks/account_lifecycle'
require_relative 'hooks/authentication'
require_relative 'hooks/session_integration'
require_relative 'hooks/rate_limiting'
require_relative 'hooks/validation'
require_relative 'hooks/error_logging'
