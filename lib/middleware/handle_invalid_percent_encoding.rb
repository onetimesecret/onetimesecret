
require 'json'
require 'logger'
require 'rack'


# Rack::HandleInvalidPercentEncoding
#
# This middleware addresses the challenge of handling malformed percent-encoded
# data in HTTP requests. Instead of attempting to guess or fix invalid encodings,
# which could lead to silent but deadly data corruption, it:
#
# 1. Detects invalid uri-encoding early in the request processing.
# 2. Returns a 400 Bad Request with a clear error message.
# 3. Logs the error for debugging and monitoring.
#
# This approach prioritizes security and transparency, providing meaningful
# feedback to API consumers and end-users while preventing potential
# application crashes or unpredictable behavior.
#
# Based on community solution by Henrik N:
# https://stackoverflow.com/questions/24648206/ruby-on-rails-invalid-byte-sequence-in-utf-8-due-to-bot/24727310#24727310
#
class Rack::HandleInvalidPercentEncoding
  @default_content_type = 'application/json'.freeze
  @default_charset      = 'utf-8'.freeze

  class << self
    attr_reader :default_content_type, :default_charset
  end

  attr_reader :logger

  def initialize(app, io: $stdout, check_enabled: nil)
    @app = app
    @logger = Logger.new(io, level: :info)
    @check_enabled = check_enabled  # override the check_enabled? method
  end

  def call(env)
    request_uri = env['REQUEST_URI']

    logger.debug "[handle-invalid-uri-encoding] Checking #{request_uri}"

    # If the route doesn't include the AppSettings module, we can't
    # determine if the app wants to check for invalid percent encoding.
    return @app.call(env) unless check_enabled?(@app)

    # The instantiated request object isn't available until later in the
    # middleware chain so we need to create our own instance here in order
    # to attempt triggering the error. We use the dup method to avoid
    # modifying the original env object.
    request = Rack::Request.new(env.dup)

    begin
      # Calling request.params is sufficient to trigger the error
      # without needing to muck further into Rack internals.
      #
      # See https://github.com/rack/rack/issues/337#issuecomment-46453404
      #
      request.params

    rescue ArgumentError => ex
      raise ex unless ex.message =~ /invalid %-encoding/

      handle_exception(env, ex)
    else

      @app.call(env)
    end
  end

  # NOTE: This check is specific to Onetime and Otto apps. We'll want to
  # find a more generic way to determine if the app/route level settings.
  # One example would be to check in config.ru and not `use` middleware
  # for apps that don't have the settings enabled.
  #
  def check_enabled?(app)
    return true if @check_enabled
    return false unless defined?(Otto) && app.is_a?(Otto)
    name, route = app.route_definitions.first
    setting_enabled = route.klass.respond_to?(:check_uri_encoding) && route.klass.check_uri_encoding
    logger.debug "[handle-invalid-uri-encoding] #{name} has settings: #{has_settings}, enabled: #{setting_enabled}"
    setting_enabled
  end

  def handle_exception(env, exception)
    rack_input = env['rack.input']&.read || ''
    env['rack.input'].rewind

    errmsg = exception.message

    logger.error "[handle-invalid-uri-encoding] #{errmsg} in #{env['REQUEST_URI']}"

    status = 400
    body   = { error: 'Bad Request', message: errmsg }.to_json

    cls = self.class
    headers = {
      'Content-Type': "#{cls.default_content_type}; charset=#{cls.default_charset}",
      'Content-Length': body.bytesize.to_s,
    }

    [status, headers, [body]]
  end
end
