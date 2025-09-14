# apps/api/v2/application.rb

require_relative '../../base_application'

require_relative 'controllers'
require_relative 'logic'

module V2
  class Application < ::BaseApplication
    @uri_prefix = '/api/v2'.freeze

    # Session middleware
    require 'onetime/session'
    use Onetime::Session, {
      expire_after: 86400, # 24 hours
      key: 'onetime.session',
      secure: OT.conf&.dig('site', 'ssl') || false,
      httponly: true,
      same_site: :lax,
      redis_prefix: 'session'
    }

    # Common middleware stack
    use Rack::DetectHost

    # Identity resolution middleware
    require 'middleware/identity_resolution'
    use Rack::IdentityResolution

    # Applications middleware stack
    use Onetime::DomainStrategy # after DetectHost
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

      # Register V2 authentication strategies
      require_relative 'auth_strategies'
      V2::AuthStrategies.register_all(router)

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end
  end
end
