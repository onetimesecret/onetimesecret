# apps/api/v2/application.rb

require 'onetime/application'
require 'onetime/middleware'

require_relative 'logic'

module V2
  class Application < Onetime::Application::Base
    @uri_prefix = '/api/v2'.freeze

    # API v2 specific middleware (common middleware is in MiddlewareStack)
    use Rack::JSONBodyParser

    warmup do
      require_relative 'logic'
      require 'onetime/models'

      # Log warmup completion
      Onetime.li 'V2 warmup completed'
    end

    protected

    def build_router
      routes_path = File.join(ENV.fetch('ONETIME_HOME'), 'apps/api/v2/routes')
      router      = Otto.new(routes_path)

      # Register authentication strategies
      require 'onetime/auth_strategies'
      Onetime::AuthStrategies.register_all(router)

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end
  end
end
