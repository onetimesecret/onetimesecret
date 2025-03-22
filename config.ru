# config.ru

# Rackup Configuration
#
# Usage:
#
#     $ thin -e dev -R config.ru -p 3000 start
#
#
# Directory structure expectations:
# ```
# /
# ├── config.ru               # Main config file
# ├── lib/
# │   ├── app_registry.rb     # Registry implementation
# │   └── onetime.rb          # Core library
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

# Environment Variables
ENV['RACK_ENV'] ||= 'production'
ENV['APP_ROOT'] = File.expand_path(__dir__).freeze
app_root = ENV['APP_ROOT']

# Directory Constants
unless defined?(PUBLIC_DIR)
  PUBLIC_DIR = File.join(app_root, '/public/web').freeze
  APP_DIR = File.join(app_root, '/apps').freeze
end

# Add main Onetime libs to the load path
$LOAD_PATH.unshift(File.join(app_root, 'lib'))

# Freshly installed operating systems don't always have their locale settings
# figured out. By setting this to UTF-8, we ensure that:
# - All file I/O operations default to UTF-8 encoding.
# - Network I/O operations treat data as UTF-8 encoded.
# - Standard input/output (STDIN, STDOUT, STDERR) uses UTF-8 encoding.
# - Strings created from external sources default to UTF-8 encoding.
# This helps maintain consistency and reduces encoding-related issues.
Encoding.default_external = Encoding::UTF_8

# Required Libraries
require 'rack/content_length'
require 'rack/contrib'

require_relative 'apps/app_registry'
require_relative 'lib/middleware'
require_relative 'lib/onetime'

# Load all applications
Dir.glob(File.join(APP_DIR, '**/application.rb')).each { |f| require f }

# Applications must be loaded before boot to ensure Familia models are registered.
# This allows proper database connection setup for all model classes.
Onetime.boot! :app

# Common middleware for all applications
use Rack::CommonLogger
use Rack::ContentLength

# If Sentry is not successfully enabled, the `Sentry` client is not
# available and this block is not executed.
Onetime.with_diagnostics do
  OT.ld "[config.ru] Sentry enabled"
  # Put Sentry middleware first to catch exceptions as early as possible
  use Sentry::Rack::CaptureExceptions
end

# Support development without code reloading in production-like environments
if defined?(OT) && OT.conf.dig(:experimental, :freeze_app)
  OT.li "[experimental] Freezing app by request (env: #{ENV['RACK_ENV']})"
  freeze_app
end

# Enable local frontend development server proxy
if ENV['RACK_ENV'] =~ /\A(dev|development)\z/

  # Validate Rack compliance
  use Rack::Lint

  # Frontend development proxy configuration
  def run_frontend_proxy
    return unless defined?(OT)
    config = OT.conf.fetch(:development, {})

    case config
    in {enabled: true, frontend_host: String => frontend_host}
      return if frontend_host.strip.empty?

      OT.li "[config.ru] Using frontend proxy for /dist to #{frontend_host}"
      require 'rack/proxy'

      # Proxy requests to the Vite dev server
      proxy_klass = Class.new(Rack::Proxy) do
        define_method(:perform_request) do |env|
          case env['PATH_INFO']
          when %r{\A/dist/} then super(env.merge('REQUEST_PATH' => env['PATH_INFO']))
          else @app.call(env)
          end
        end
      end

      use proxy_klass, backend: frontend_host
    else
      OT.ld "[config.ru] Not running frontend proxy"
    end
  end

  # Add development middleware
  use Rack::Reloader, 1
  run_frontend_proxy
end

# Mount all applications
run Rack::URLMap.new(AppRegistry.build)
