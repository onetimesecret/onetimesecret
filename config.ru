# Onetime Rackup
#
# Usage:
#
#     $ thin -e dev -R config.ru -p 7143 start
#     $ tail -f /var/log/system.log

ENV['RACK_ENV'] ||= 'prod'
ENV['APP_ROOT'] = ::File.expand_path(::File.join(::File.dirname(__FILE__)))
$:.unshift(::File.join(ENV['APP_ROOT']))
$:.unshift(::File.join(ENV['APP_ROOT'], 'lib'))
$:.unshift(::File.join(ENV['APP_ROOT'], 'app'))

require 'otto'
require 'onetime/app/web'
require 'onetime/app/api'
require 'onetime/app/colonel'

PUBLIC_DIR = "#{ENV['APP_ROOT']}/public/web"
APP_DIR = "#{ENV['APP_ROOT']}/lib/onetime/app"

apps = {
  '/'           => Otto.new("#{APP_DIR}/web/routes"),
  '/api'        => Otto.new("#{APP_DIR}/api/routes"),
  '/colonel'    => Otto.new("#{APP_DIR}/colonel/routes")
}

Onetime.load! :app

if Otto.env?(:dev)
  # DEV: Run web apps with extra logging and reloading
  apps.each_pair do |path,app|
    map(path) {
      use Rack::CommonLogger
      use Rack::Reloader, 1
      app.option[:public] = PUBLIC_DIR
      app.add_static_path '/favicon.ico'
      # TODO: Otto should check for not_found method instead of settign it here.
      #otto.not_found = [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
      run app
    }
  end
else
  # PROD: run barebones webapps
  apps.each_pair do |path,app|
    map(path) { run app }
  end
  #$SAFE = 1  # http://www.rubycentral.com/pickaxe/taint.html
end
