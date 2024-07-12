
require 'rack'
require 'logger'


# Rack::HandleInvalidPercentEncoding
#
# This middleware addresses the challenge of handling malformed percent-encoded
# data in HTTP requests. Instead of attempting to guess or fix invalid encodings,
# which could lead to silent but deadly data corruption, it:
#
# 1. Detects invalid percent-encoding early in the request processing.
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
  @default_content_type = 'application/json'
  @default_charset      = 'utf-8'

  class << self
    attr_reader :default_content_type, :default_charset
  end

  attr_reader :logger

  def initialize(app, io: $stdout)
    @app = app
    @logger = Logger.new(io)
  end

  def call(env)

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

    rescue ArgumentError => e
      raise e unless e.message =~ /invalid %-encoding/
      rack_input = request.get_header('rack.input').read

      message = "`#{e.message}` in one of the following params: #{rack_input}"
      logger.info "[handle-invalid-percent-encoding] #{message}"
      content_type = env['HTTP_ACCEPT'] || self.class.default_content_type
      status = 400
      body   = { error: 'Bad Request', message: e.message }.to_json
      return [
        status,
        {
          'Content-Type': "#{content_type}; charset=#{self.class.default_charset}",
           'Content-Length': body.bytesize.to_s
        },
        [body]
      ]
    else

      @app.call(env)
    end
  end
end
