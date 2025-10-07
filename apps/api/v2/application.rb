# apps/api/v2/application.rb

require 'onetime/application'
require 'onetime/middleware'
require 'onetime/models'

require_relative 'logic'

module V2
  class Application < Onetime::Application::Base
    @uri_prefix = '/api/v2'.freeze

    # API v2 specific middleware (common middleware is in MiddlewareStack)
    use Rack::JSONBodyParser

    warmup do
    end

    protected

    def build_router
      routes_path = File.join(__dir__, 'routes')
      router      = Otto.new(routes_path)

      # Register authentication strategies
      Onetime::Application::AuthStrategies.register_all(router)

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end
  end
end
