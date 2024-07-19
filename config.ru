# frozen_string_literal: true

#
#
# Usage:
#
#     $ thin -e dev -R config.ru -p 3000 start
#     $ tail -f /var/log/system.log

# Ensure immediate flushing of stdout to improve real-time logging visibility.
# This is particularly useful in development and production environments where
# timely log output is crucial for monitoring and debugging purposes.
#
# Note: This setting can have a performance impact in high-throughput environments.
#
# See: https://www.rubydoc.info/gems/rack/Rack/CommonLogger
#
$stdout.sync = true

ENV['RACK_ENV'] ||= 'production'
ENV['APP_ROOT'] = File.expand_path(File.join(File.dirname(__FILE__)))
$LOAD_PATH.unshift(File.join(ENV.fetch('APP_ROOT')))
$LOAD_PATH.unshift(File.join(ENV.fetch('APP_ROOT', nil), 'lib'))
$LOAD_PATH.unshift(File.join(ENV.fetch('APP_ROOT', nil), 'app'))

require_relative 'lib/onetime'

require_relative 'lib/middleware/header_logger_middleware'
require_relative 'lib/middleware/handle_invalid_percent_encoding'
require_relative 'lib/middleware/handle_invalid_utf8'

PUBLIC_DIR = "#{ENV.fetch('APP_ROOT', nil)}/public/web".freeze
APP_DIR = "#{ENV.fetch('APP_ROOT', nil)}/lib/onetime/app".freeze

apps = {
  '/'           => Otto.new("#{APP_DIR}/web/routes"),
  '/api'        => Otto.new("#{APP_DIR}/api/routes"),
  '/colonel'    => Otto.new("#{APP_DIR}/colonel/routes")
}

Onetime.boot! :app

middlewares = if Otto.env?(:dev)
  [
    [Rack::CommonLogger],
    [Rack::Reloader, 1],
    [Rack::HeaderLoggerMiddleware],
    [Rack::HandleInvalidUTF8],
    [Rack::HandleInvalidPercentEncoding]
  ]
else
  [
    [Rack::CommonLogger],
    [Rack::HandleInvalidUTF8],
    [Rack::HandleInvalidPercentEncoding]
  ]
end

apps.each_pair do |path, app|
  map(path) {
    OT.info "[app] Attaching #{app} at #{path}"

    middlewares.each do |klass, *args|
      OT.ld "[middleware] Attaching #{klass}"
      use klass, *args
    end
    app.option[:public] = PUBLIC_DIR
    run app
  }
end
