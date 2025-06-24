# apps/api/v1/application.rb

require_relative '../../base_application'

require_relative 'models'
require_relative 'logic'
require_relative 'controllers'

module V1
  class Application < ::BaseApplication
    @uri_prefix = '/api/v1'

    # Common middleware stack
    use Rack::HandleInvalidUTF8
    use Rack::HandleInvalidPercentEncoding
    use Rack::ClearSessionMessages
    use Rack::DetectHost

    # Applications middleware stack
    use Onetime::DomainStrategy

    warmup do
      require_relative 'logic'
      require_relative 'models'

      V1::RateLimit.register_events OT.conf&.dig(:limits) || {}

      # Log warmup completion
      Onetime.li "V1 warmup completed"
    end

    protected

    def build_router
      routes_path = File.join(ENV['ONETIME_HOME'], 'apps/api/v1/routes')
      router = Otto.new(routes_path)

      # Default error responses
      headers = { 'Content-Type' => 'application/json' }
      router.not_found = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end

  end
end
