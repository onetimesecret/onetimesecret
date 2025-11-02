# apps/api/v2/application.rb

require 'onetime/application'
require 'onetime/middleware'
require 'onetime/models'

require_relative 'logic'
require_relative 'auth_strategies'

module V2
  class Application < Onetime::Application::Base
    @uri_prefix = '/api/v2'.freeze

    # API v2 specific middleware (common middleware is in MiddlewareStack)
    use Rack::JSONBodyParser # TODO: Remove since we pass: builder.use Rack::Parser, parsers: @parsers

    # CSRF Protection - Token-based approach for JSON API
    use Rack::Protection::AuthenticityToken, reaction: :drop_session
    use Onetime::Middleware::CsrfResponseHeader

    warmup do
    end

    protected

    def build_router
      routes_path = File.join(__dir__, 'routes')
      router      = Otto.new(routes_path)

      # IP privacy is enabled globally in common middleware stack for public
      # addresses. Must be enabled specifically for private and localhost
      # addresses. See Otto::Middleware::IPPrivacy for details
      router.enable_full_ip_privacy!

      # Register authentication strategies
      V2::AuthStrategies.register_essential(router)

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end
  end
end
