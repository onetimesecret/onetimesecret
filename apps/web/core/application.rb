# apps/web/core/application.rb

require_relative '../../base_application'

require_relative 'controllers'

module Core
  class Application < ::BaseApplication
    @uri_prefix = '/'.freeze

    # Common middleware stack
    use Rack::ClearSessionMessages
    use Rack::DetectHost

    # Applications middleware stack
    use Onetime::DomainStrategy

    warmup do
      # Expensive initialization tasks go here

      # Log warmup completion
      Onetime.li 'Manifold warmup completed'
    end

    protected

    def build_router
      routes_path = File.join(Onetime::HOME, 'apps/web/core/routes')
      router      = Otto.new(routes_path)

      # Enable CSP nonce support for enhanced security
      router.enable_csp_with_nonce!(debug: OT.debug?)

      # Default error responses
      headers             = { 'content-type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
