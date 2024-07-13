require 'pry-byebug'
require 'json'
require 'logger'
require 'rack'
require 'rack/utf8_sanitizer'

# Rack::HandleInvalidUTF8
#
# Handles invalid UTF8 characters in request URI and headers by
# raising an exception and returning a 400 Bad Request response.
#
class Rack::HandleInvalidUTF8 < Rack::UTF8Sanitizer
  @default_content_type = 'application/json'
  @default_charset      = 'utf-8'

  class << self
    attr_reader :default_content_type, :default_charset
  end

  attr_reader :logger

  def initialize(app, options = {}, io: $stdout)
    options[:strategy] = :exception
    super(app, options)
    @logger = Logger.new(io)
  end

  def call(env)

    sanitize(env.dup)

  rescue Rack::UTF8Sanitizer::NullByteInString,
         Encoding::InvalidByteSequenceError,
         Encoding::CompatibilityError,
         Encoding::UndefinedConversionError => e

    return handle_exception(env, e)
  else

    @app.call(env)
  end

  private

  def handle_exception(env, exception)
    message = "Invalid UTF-8 or null byte detected: #{exception.message}"
    logger.info "[handle-invalid-utf8] #{message}"

    status = 400
    body = { error: 'Bad Request', message: message }.to_json

    cls = self.class
    headers = {
      'Content-Type': "#{cls.default_content_type}; charset=#{cls.default_charset}",
      'Content-Length': body.bytesize.to_s
    }

    [status, headers, [body]]
  end
end
