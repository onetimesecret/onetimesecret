# apps/api/v1/application.rb

require_relative '../../base_application'

require_relative 'models'
require_relative 'logic'
require_relative 'controllers'
require_relative 'utils'

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

      # NOTE: When the mutual config is saved to redis incorrectly, it can come
      # out here as a serialized JSON string, leading to:
      #
      # rate_limit.rb:189:in 'Hash#merge!':
      #   no implicit conversion of String into Hash
      #
      # V1::RateLimit.register_events OT.conf&.dig(:limits) || {}

      V1::Plan.load_plans!

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
