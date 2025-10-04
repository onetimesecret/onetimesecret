# apps/api/v2/application.rb

require 'base_application'
require 'onetime/middleware'

require_relative 'app'

module V2
  class Application < ::BaseApplication
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
      # Return the V2 app instance
      V2::App.new
    end
  end
end
