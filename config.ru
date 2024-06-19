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

require 'otto'
require 'onetime/app/web'
require 'onetime/app/api'
require 'onetime/app/colonel'

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
    Otto.debug = true
  end

  # DEV: Run web apps with extra logging and reloading
  apps.each_pair do |path, app|
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
    app.option[:public] = PUBLIC_DIR
    map(path) { run app }
  end
end
