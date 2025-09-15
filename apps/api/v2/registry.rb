# apps/api/v2/application.rb

require 'base_application'
require 'onetime/middleware'

require_relative 'app'

module V2
  class Application < ::BaseApplication
    @uri_prefix = '/api/v2'.freeze

    # Session middleware
    require 'onetime/session'
    use Onetime::Session, {
      expire_after: 86_400, # 24 hours
      key: 'onetime.session',
      secure: OT.conf&.dig('site', 'ssl') || false,
      httponly: true,
      same_site: :lax,
      redis_prefix: 'session',
    }

    # Common middleware stack
    use Rack::DetectHost

    # Identity resolution middleware
    use Onetime::Middleware::IdentityResolution

    # Applications middleware stack
    use Onetime::Middleware::DomainStrategy # after DetectHost
    use Rack::JSONBodyParser

    warmup do
      require_relative 'logic'
      require 'onetime/models'

      # Log warmup completion
      Onetime.li 'V2 warmup completed'
    end

    protected

    def build_router
      # Return the V2 app instance
      V2::App.new
    end
  end
end
