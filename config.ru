# frozen_string_literal: true

# Rackup Configuration
#
# Usage:
#
#     $ thin -e dev -R config.ru -p 3000 start
#

ENV['RACK_ENV'] ||= 'production'
ENV['APP_ROOT'] = File.expand_path(__dir__).freeze
app_root = ENV['APP_ROOT']

PUBLIC_DIR = File.join(app_root, '/public/web').freeze
APP_DIR = File.join(app_root, '/lib/onetime/app').freeze

$LOAD_PATH.unshift(File.join(app_root, 'lib'))

require 'rack/content_length'

require_relative 'lib/middleware'
require_relative 'lib/onetime'

Onetime.boot! :app

# Create the Rack apps for each routes file
apps = {
  '/api/v1'   =>  '/api/v1/routes',
  '/api/v2'   =>  '/api/v2/routes',
  '/'         =>  '/web/routes'
}.transform_values { |path| Otto.new(File.join(APP_DIR, path)) }

# Add "last resort" json responses for the API
headers = { 'Content-Type' => 'application/json' }
apps['/api/v1'].not_found = [404, headers, [{ error: 'Not Found' }.to_json]]
apps['/api/v1'].server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]
apps['/api/v2'].not_found = apps['/api/v1'].not_found
apps['/api/v2'].server_error = apps['/api/v1'].server_error

# Assign an absolute path to the directory for static assets
# for the "root" web endpoint.
apps['/'].option[:public] = PUBLIC_DIR

# Middleware Configuration
#
# A centralized middleware stack provides an overview of the
# active middleware in each environment and simplifies
# comparison and debugging. NOTE: The order is important.
middlewares = if Otto.env?(:dev)
  [
    [Rack::CommonLogger],
    [Rack::ClearSessionMessages],
    [Rack::Reloader, 1],
    [Rack::HandleInvalidUTF8],
    [Rack::HandleInvalidPercentEncoding],
    [Rack::ContentLength]
  ]
else
  [
    [Rack::CommonLogger],
    [Rack::ClearSessionMessages],
    [Rack::HandleInvalidUTF8],
    [Rack::HandleInvalidPercentEncoding],
    [Rack::ContentLength]
  ]
end

# Mount Applications
#
# Apply the middleware for each application and mount it to the
# URI path it'll respond to when a request is made (e.g. /api).
apps.each_pair do |path, app|
  map(path) do
    OT.info "[app] Mounting #{app.class} at #{path}"

    # e.g. use Rack::CommonLogger
    middlewares.each do |middleware_class, *args|
      OT.ld "[middleware] Applying #{middleware_class}"
      use middleware_class, *args
    end

    run app
  end
end
