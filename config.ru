# frozen_string_literal: true

#
#
# Usage:
#
#     $ thin -e dev -R config.ru -p 3000 start
#     $ tail -f /var/log/system.log

$stdout.sync = true

ENV['RACK_ENV'] ||= 'prod'
ENV['APP_ROOT'] = File.expand_path(File.join(File.dirname(__FILE__)))
$LOAD_PATH.unshift(File.join(ENV.fetch('APP_ROOT')))
$LOAD_PATH.unshift(File.join(ENV.fetch('APP_ROOT', nil), 'lib'))
$LOAD_PATH.unshift(File.join(ENV.fetch('APP_ROOT', nil), 'app'))

require 'onetime'

PUBLIC_DIR = "#{ENV.fetch('APP_ROOT', nil)}/public/web".freeze
APP_DIR = "#{ENV.fetch('APP_ROOT', nil)}/lib/onetime/app".freeze

apps = {
  '/'           => Otto.new("#{APP_DIR}/web/routes"),
  '/api'        => Otto.new("#{APP_DIR}/api/routes"),
  '/colonel'    => Otto.new("#{APP_DIR}/colonel/routes")
}

Onetime.boot! :app

SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)

class HeaderLoggerMiddleware
  def initialize(app)
    @app = app
    SYSLOG.info("HeaderLoggerMiddleware initialized")
  end

  def call(env)
    log_headers(env)
    @app.call(env)
  end

  private

  def log_headers(env)
    SYSLOG.info("Request Headers for #{env['REQUEST_METHOD']} #{env['PATH_INFO']}:")
    env.each do |key, value|
      if key.start_with?('HTTP_')
        header_name = key.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-')
        SYSLOG.info("  #{header_name}: #{value}")
      end
    end
    SYSLOG.info("\n")  # Add a blank line for readability between requests
  end
end

if Otto.env?(:dev)

  if Onetime.debug
    require 'pry-byebug'
    #Otto.debug = true
  end

  # DEV: Run web apps with extra logging and reloading
  apps.each_pair do |path, app|
    use HeaderLoggerMiddleware
    map(path) do
      use Rack::CommonLogger
      use Rack::Reloader, 1
      app.option[:public] = PUBLIC_DIR
      app.add_static_path '/favicon.ico'
      # TODO: Otto should check for not_found method instead of setting it here.
      # otto.not_found = [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
      run app
    end
  end

else
  # PROD: run barebones webapps
  apps.each_pair do |path, app|
    use HeaderLoggerMiddleware
    app.option[:public] = PUBLIC_DIR
    map(path) { run app }
  end
end
