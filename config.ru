# config.ru
#
# Main Rack configuration file for the OneTime Secret application.
# This file orchestrates the entire application stack, sets up middleware,
# and defines the application's runtime environment.
#
# Usage:
#   $ thin -e dev -R config.ru -p 3000 start
#
# Application Structure:
# ```
# /
# ├── config.ru               # Main Rack configuration
# ├── lib/
# │   ├── app_registry.rb     # Application registry implementation
# │   └── onetime.rb          # Core OneTime Secret library
# └── apps/
#     ├── api/
#     │   ├── v1/
#     │   │   ├── config.ru   # V1 API registration
#     │   │   └── application.rb
#     │   ├── v2/
#     │   │   ├── config.ru   # V2 API registration
#     │   │   └── application.rb
#     │   └── v3/
#     │       ├── config.ru   # Roda app registration
#     │       └── roda_app.rb
#     └── web/
#         ├── config.ru       # Web app registration
#         └── application.rb
# ```
#

# Environment Configuration
# -------------------------------
# Set default environment variables and establish directory structure constants.
# These fundamentals ensure the application knows where to find its resources.
ENV['RACK_ENV'] ||= 'production'
ENV['ONETIME_HOME'] ||= File.expand_path(__dir__).freeze
project_root = ENV['ONETIME_HOME']
app_root = File.join(project_root, '/apps').freeze

# Public Directory Configuration
# Define the location for static web assets
unless defined?(PUBLIC_DIR)
  PUBLIC_DIR = File.join(project_root, '/public/web').freeze
end

# Load Path Configuration
# Add the lib directory to Ruby's load path for require statements
$LOAD_PATH.unshift(File.join(project_root, 'lib'))

# Character Encoding Configuration
# Set UTF-8 as the default external encoding to ensure consistent text handling:
# - Standardizes file and network I/O operations
# - Normalizes STDIN/STDOUT/STDERR encoding
# - Provides default encoding for strings from external sources
# This prevents encoding-related bugs, especially on fresh OS installations
# where locale settings may not be properly configured.
Encoding.default_external = Encoding::UTF_8

# Dependencies and Core Libraries
# -------------------------------
# Load required Rack extensions and application modules
require 'rack/content_length'
require 'rack/contrib'
require 'rack/protection'
require 'rack/utf8_sanitizer'

# Load application-specific components
require_relative 'apps/app_registry'    # Application registry for mounting apps
require_relative 'lib/onetime'          # Core OneTime Secret functionality
require_relative 'lib/onetime/middleware' # Custom middleware components

# Application Initialization
# -------------------------------
# Load all application modules from the registry
AppRegistry.load_applications
BaseApplication.register_applications

# Bootstrap the Application
# Applications must be loaded before boot to ensure all Familia models
# are properly registered. This sequence is critical for establishing
# database connections for all model classes.
Onetime.boot! :app

# Middleware Configuration
# -------------------------------

# Standard Middleware Setup
# Configure essential middleware components for all environments
if !Onetime.conf.dig(:logging, :http_requests).eql?(false)
  Onetime.li "[config.ru] Request logging with Rack::CommonLogger enabled"
  use Rack::CommonLogger  # Log HTTP requests in standard format
end
use Rack::ContentLength  # Automatically set Content-Length header

# Error Monitoring Integration
# Add Sentry exception tracking when available
# This block only executes if Sentry was successfully initialized
Onetime.with_diagnostics do
  Onetime.ld "[config.ru] Sentry enabled"
  # Position Sentry middleware early to capture exceptions throughout the stack
  use Sentry::Rack::CaptureExceptions
end

# Performance Optimization
# Support running with code frozen in production-like environments
# This reduces memory usage and prevents runtime modifications
if Onetime.conf.dig(:experimental, :freeze_app)
  Onetime.li "[experimental] Freezing app by request (env: #{ENV['RACK_ENV']})"
  freeze_app
end

# Development Environment Configuration
# Enable development-specific middleware when in development mode
# This handles code validation and frontend development server integration
if BaseApplication.development?
  require_relative 'lib/onetime/middleware/vite_proxy'
  use Onetime::Middleware::ViteProxy
end

# Production Environment Configuration
# Serve static frontend assets in production mode
# While reverse proxies often handle static files in production,
# this provides a fallback capability for simpler deployments.
#
# Note: This explicit configuration replaces the implicit functionality
# that existed prior to v0.21.0 release.
if BaseApplication.production?
  require_relative 'lib/onetime/middleware/static_files'
  use Onetime::Middleware::StaticFiles
end

# Security Middleware Configuration
# Each middleware component can be enabled/disabled via configuration
middleware_settings = Onetime.conf.dig(:experimental, :middleware)
p [:plop, middleware_settings]
if middleware_settings
  # UTF-8 Sanitization - Ensures proper UTF-8 encoding in request parameters
  if middleware_settings[:utf8_sanitizer]
    Onetime.ld "[config.ru] Enabling UTF8Sanitizer middleware"
    use Rack::UTF8Sanitizer, sanitize_null_bytes: true
  end

  # Protection against CSRF attacks
  if middleware_settings[:http_origin]
    Onetime.ld "[config.ru] Enabling HttpOrigin protection"
    use Rack::Protection::HttpOrigin
  end

  # Escapes HTML in parameters to prevent XSS
  if middleware_settings[:escaped_params]
    Onetime.ld "[config.ru] Enabling EscapedParams protection"
    use Rack::Protection::EscapedParams
  end

  # Sets X-XSS-Protection header
  if middleware_settings[:xss_header]
    Onetime.ld "[config.ru] Enabling XSSHeader protection"
    use Rack::Protection::XSSHeader
  end

  # Prevents clickjacking via X-Frame-Options
  if middleware_settings[:frame_options]
    Onetime.ld "[config.ru] Enabling FrameOptions protection"
    use Rack::Protection::FrameOptions
  end

  # Blocks directory traversal attacks
  if middleware_settings[:path_traversal]
    Onetime.ld "[config.ru] Enabling PathTraversal protection"
    use Rack::Protection::PathTraversal
  end

  # Prevents session fixation via manipulated cookies
  if middleware_settings[:cookie_tossing]
    Onetime.ld "[config.ru] Enabling CookieTossing protection"
    use Rack::Protection::CookieTossing
  end

  # Prevents IP spoofing attacks
  if middleware_settings[:ip_spoofing]
    Onetime.ld "[config.ru] Enabling IPSpoofing protection"
    use Rack::Protection::IPSpoofing
  end

  # Forces HTTPS connections via HSTS headers
  if middleware_settings[:strict_transport]
    Onetime.ld "[config.ru] Enabling StrictTransport protection"
    use Rack::Protection::StrictTransport
  end
end

# Application Mounting
# Map all registered applications to their respective URL paths
run Rack::URLMap.new(AppRegistry.build)
