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
class Rack::HandleInvalidUTF8
  @default_content_type = 'application/json'
  @default_charset      = 'utf-8'
  @default_exception    = Encoding::InvalidByteSequenceError
  @input_sources        = %w[
    SCRIPT_NAME
    REQUEST_PATH
    REQUEST_URI
    PATH_INFO
    QUERY_STRING
    HTTP_REFERER
    ORIGINAL_FULLPATH
    ORIGINAL_SCRIPT_NAME
    SERVER_NAME
    HTTP_USER_AGENT

    # Body content
    rack.input
  ]

  class << self
    attr_reader :default_content_type,
                :default_charset,
                :default_exception,
                :input_sources
  end

  attr_reader :logger

  def initialize(app, io: $stdout)
    @app = app
    @logger = Logger.new(io)
  end

  def call(env)
    shallow_copy = env.dup

    # We duplicate the environment to avoid modifying the original
    # since all we want to do is kick the tires and see what shakes
    # out. We don't want to change the environment and continue; we
    # want to raise an exception early so we can return a 400 Bad
    # Request and a descriptive error message.
    self.class.input_sources.each do |key|
      next unless shallow_copy.key?(key)
      check_and_raise_for_invalid_utf8(shallow_copy[key], key)
    end

  rescue Encoding::InvalidByteSequenceError,
         Encoding::CompatibilityError,
         Encoding::UndefinedConversionError => e

    return handle_exception(env, e)
  else

    @app.call(env)
  end

  private

  # Validates that the input is valid UTF-8 and raises an exception if it's not.
  #
  # This method handles different input types (String, StringIO, IO) and checks
  # if the content is valid UTF-8. If the input is not valid UTF-8, it raises an exception.
  #
  # @param input [String, StringIO, IO, nil] The input to be validated
  # @param key [String] The environment key being validated. Used for exception message.
  # @return [nil] if the input is valid UTF-8
  # @raise [StandardError] if the input contains invalid UTF-8 characters
  #   The exact exception class is determined by self.class.default_exception
  #
  # @example
  #   check_and_raise_for_invalid_utf8("Hello, world!", "QUERY_STRING") # => nil
  #   check_and_raise_for_invalid_utf8(StringIO.new("\xFF"), "rack.input") # raises an exception
  #   check_and_raise_for_invalid_utf8(nil, "SOME_KEY") # => nil (empty string is valid UTF-8)

  def check_and_raise_for_invalid_utf8(input, key)
    # If the string is frozen, we need to dup it before modifying
    input = input.dup if input.frozen?

    testcase = case input
        when String
          input
        when StringIO, IO
          input.read
        else
          '' # includes nil
        end

    testcase.force_encoding('UTF-8')
    return if testcase.valid_encoding?
    raise self.class.default_exception, "Invalid UTF-8 detected in env['#{key}']"
  end

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
