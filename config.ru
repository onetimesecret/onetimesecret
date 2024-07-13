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
$stdout.sync = true

ENV['RACK_ENV'] ||= 'prod'
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

if Otto.env?(:dev)

  if Onetime.debug
    require 'pry-byebug'
  end

  # DEV: Run webapps with extra logging and reloading
  apps.each_pair do |path, app|
    use HeaderLoggerMiddleware
    map(path) do
      OT.ld "[app] Attaching #{app} at #{path}"
      use Rack::CommonLogger
      use Rack::Reloader, 1

      use HeaderLoggerMiddleware
      use Rack::HandleInvalidUTF8
      use Rack::HandleInvalidPercentEncoding

      app.option[:public] = PUBLIC_DIR
      app.add_static_path '/favicon.ico'

      run app
    end
  end

else

  # PROD: run webapps the bare minimum additional middleware
  apps.each_pair do |path, app|
    use HeaderLoggerMiddleware
    use Rack::HandleInvalidUTF8
    use Rack::HandleInvalidPercentEncoding

    app.option[:public] = PUBLIC_DIR
    map(path) { run app }
  end
end
