# frozen_string_literal: true

# Rackup Configuration
#
# Usage:
#
#     $ thin -e dev -R config.ru -p 3000 start
#

# Environment Variables
ENV['RACK_ENV'] ||= 'production'
ENV['APP_ROOT'] = File.expand_path(__dir__).freeze
app_root = ENV['APP_ROOT']

# Directory Constants
PUBLIC_DIR = File.join(app_root, '/public/web').freeze
APP_DIR = File.join(app_root, '/lib/onetime/app').freeze

# Load Paths
$LOAD_PATH.unshift(File.join(app_root, 'lib'))

# Required Libraries
require 'rack/content_length'
require_relative 'lib/middleware'
require_relative 'lib/onetime'

# Boot Application
Onetime.boot! :app

# Rack Applications Configuration
apps = {
  '/api/v1' => '/api/v1/routes',
  '/api/v2' => '/api/v2/routes',
  '/'       => '/web/routes'
}.transform_values { |path| Otto.new(File.join(APP_DIR, path)) }

# JSON Response Headers
headers = { 'Content-Type' => 'application/json' }

# API Error Responses
[1, 2].each do |version|
  apps["/api/v#{version}"].not_found = [404, headers, [{ error: 'Not Found' }.to_json]]
  apps["/api/v#{version}"].server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]
end

# Public Directory for Root Endpoint
apps['/'].option[:public] = PUBLIC_DIR

# Middleware Stack Configuration
middleware_stack = [
  [Rack::CommonLogger],
  [Rack::ClearSessionMessages],
  [Rack::HandleInvalidUTF8],
  [Rack::HandleInvalidPercentEncoding],
  [Rack::ContentLength]
]
middleware_stack.insert(2, [Rack::Reloader, 1]) if Otto.env?(:dev)

# Mount Applications with Middleware
apps.each_pair do |path, app|
  map(path) do
    OT.info "Mounting #{app.class} at #{path}"

    middleware_stack.each do |middleware_class, *args|
      OT.ld "[middleware] Applying #{middleware_class}"
      use middleware_class, *args
    end

    run app
  end
end
