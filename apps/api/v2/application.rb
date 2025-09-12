# apps/api/v2/application.rb

require_relative '../../base_application'

require_relative 'models'
require_relative 'logic'
require_relative 'controllers'

module V2
  class Application < ::BaseApplication
    @uri_prefix = '/api/v2'.freeze

    # Session middleware
    require_relative '../../../lib/rack/session/redis_familia'
    use Rack::Session::RedisFamilia, {
      expire_after: 86400, # 24 hours
      key: 'ots.session',
      secure: OT.conf&.dig('site', 'ssl') || false,
      httponly: true,
      same_site: :lax,
      redis_prefix: 'session'
    }

    # Common middleware stack
    use Rack::DetectHost

    # Applications middleware stack
    use Onetime::DomainStrategy # after DetectHost
    use Rack::JSONBodyParser

    warmup do
      require_relative 'logic'
      require_relative 'models'

      # Log warmup completion
      Onetime.li 'V2 warmup completed'
    end

    protected

    def build_router
      routes_path = File.join(ENV.fetch('ONETIME_HOME'), 'apps/api/v2/routes')
      router      = Otto.new(routes_path)

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end
  end
end
