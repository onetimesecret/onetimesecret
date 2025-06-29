# apps/web/manifold/application.rb

require_relative '../../base_application'

require_relative 'controllers'

# TODO: Rename. UI? Spigot? Manifold? Pylon? Ferrule? Abutment? Rootstock?
module Manifold
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
      routes_path = File.join(ENV.fetch('ONETIME_HOME'), 'apps/web/manifold/routes')
      router      = Otto.new(routes_path)

      # Default error responses
      headers             = { 'Content-Type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
