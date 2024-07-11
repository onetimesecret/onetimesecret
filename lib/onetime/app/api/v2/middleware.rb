

# Locale - Rack Middleware
# This middleware is responsible for setting and managing the locale for the application.
# It determines the appropriate locale based on various factors such as user preferences,
# request headers, or default settings.
#
# The `locale` method:
# - Retrieves the current locale setting for the request
# - Can be used throughout the application to ensure consistent localization
# - May consider factors like:
#   - User's preferred language settings
#   - Accept-Language HTTP header
#   - Geo-location data (if available)
#   - Default locale set in the application config
#
# Usage:
#   The `locale` method is called in various parts of the application, such as in the
#   `status` and `version` methods above, to include the current locale in API responses.
#
# Note: Ensure that the locale middleware is properly configured in your application's
# middleware stack for this functionality to work correctly.


# Rack middleware example
# This example demonstrates how to implement a simple Rack middleware that logs the request URL and method.
# The middleware intercepts the request, logs the URL and method, and then passes the request to the next middleware in the stack.
#
# The `call` method:
# - Receives the request environment hash as an argument
# - Logs the request URL and method
# - Calls the `app` method to pass the request to the next middleware in the stack
#
# Usage:
#   To use this middleware, add it to your application's middleware stack in the `config.ru` file.
#   For example:
#   ```ruby
#   use SimpleLoggerMiddleware
#   run YourApp
#   ```
#
# Note: This middleware is a simple example and may need to be modified or extended for more complex logging requirements.
class SimpleLoggerMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Log the request URL and method
    puts
    puts "Request URL: #{env['REQUEST_URI']}"
  end
end

class LocaleMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Request phase
    puts "LocaleMiddleware: Processing request"

    # Set locale based on request
    requested_locale = extract_locale_from_request(env)
    I18n.with_locale(requested_locale) do
      # Pass the request to the next middleware or the application
      status, headers, body = @app.call(env)

      # Response phase
      puts "LocaleMiddleware: Processing response"

      # Modify the response
      headers['Content-Language'] = I18n.locale.to_s

      # Return the (potentially modified) response
      [status, headers, body]
    end
  end

  private

  def extract_locale_from_request(env)
    # Logic to determine locale from request
    # This could check headers, params, etc.
    env['HTTP_ACCEPT_LANGUAGE']&.scan(/^[a-z]{2}/)&.first || I18n.default_locale
  end
end

class RateLimitMiddleware
  def initialize(app)
    @app = app
    @request_count = Hash.new(0)
  end

  def call(env)
    client_ip = env['REMOTE_ADDR']

    if rate_limit_exceeded?(client_ip)
      # Terminate the request early
      return rate_limit_response
    end

    # If rate limit not exceeded, increment counter and pass to next middleware
    @request_count[client_ip] += 1
    @app.call(env)
  end

  private

  def rate_limit_exceeded?(client_ip)
    @request_count[client_ip] >= 100 # Limit to 100 requests per client
  end

  def rate_limit_response
    [
      429, # HTTP status code for "Too Many Requests"
      {
        'Content-Type' => 'application/json',
        'Retry-After' => '3600' # Suggest retry after 1 hour
      },
      [{ error: 'Rate limit exceeded. Please try again later.' }.to_json]
    ]
  end
end
