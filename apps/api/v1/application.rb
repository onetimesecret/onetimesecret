# apps/api/v1/application.rb

require_relative '../../base_application'

require_relative 'models'
require_relative 'logic'
require_relative 'controllers'
require_relative 'utils'

module V1
  class Application < ::BaseApplication
    @uri_prefix = '/api/v1'

    # Session middleware
    require_relative '../../../lib/onetime/session'
    use Onetime::Session, {
      expire_after: 86400, # 24 hours
      key: 'onetime.session',
      secure: OT.conf&.dig('site', 'ssl') || false,
      httponly: true,
      same_site: :lax,
      redis_prefix: 'session'
    }

    # Common middleware stack
    use Rack::HandleInvalidUTF8
    use Rack::HandleInvalidPercentEncoding
    use Rack::DetectHost

    # Identity resolution middleware
    require_relative '../../../lib/middleware/identity_resolution'
    use Rack::IdentityResolution

    # Applications middleware stack
    use Onetime::DomainStrategy

    warmup do
      require_relative 'logic'
      require_relative 'models'

      # Log warmup completion
      Onetime.li "V1 warmup completed"
    end

    protected

    def build_router
      routes_path = File.join(ENV['ONETIME_HOME'], 'apps/api/v1/routes')
      router = Otto.new(routes_path)

      # Default error responses
      headers = { 'content-type' => 'application/json' }
      router.not_found = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end

  end
end
