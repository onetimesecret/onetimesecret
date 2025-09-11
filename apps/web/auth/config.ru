# apps/web/auth/config.ru

require 'bundler/setup'
require_relative 'auth'

# Configure the application
if ENV['RACK_ENV'] == 'production'
  # Production configuration
  use Rack::Deflater  # Gzip compression

  # Security headers
  use Rack::Protection::AuthenticityToken
  use Rack::Protection::ContentSecurityPolicy
  use Rack::Protection::FrameOptions
  use Rack::Protection::HttpOrigin
  use Rack::Protection::IPSpoofing
  use Rack::Protection::JsonCsrf
  use Rack::Protection::PathTraversal
  use Rack::Protection::SessionHijacking
end

# Request logging
use Rack::CommonLogger

# Run the authentication service
run AuthService.freeze.app
