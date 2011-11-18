# Onetime Rackup
#
# Usage:
# 
#     $ bundle exec thin -e dev -R config.ru -p 7143 start
#     $ tail -f /var/log/system.log

ENV['RACK_ENV'] ||= 'prod'
ENV['APP_ROOT'] = ::File.expand_path(::File.join(::File.dirname(__FILE__)))
$:.unshift(::File.join(ENV['APP_ROOT']))
$:.unshift(::File.join(ENV['APP_ROOT'], 'lib'))
$:.unshift(::File.join(ENV['APP_ROOT'], 'app'))

require 'otto'
require 'onetime/app/site'

PUBLIC_DIR = "#{ENV['APP_ROOT']}/public/site"

otto = Otto.new("#{ENV['APP_ROOT']}/lib/onetime/app/routes")
# TODO: Otto should check for not_found method instead of settign it here.
#otto.not_found = [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
otto.option[:public] = PUBLIC_DIR
otto.add_static_path '/favicon.ico'

Onetime.load! :app

if Otto.env?(:dev)
  map("/") {
    use Rack::CommonLogger
    use Rack::Reloader, 0
    run otto
  }
else
  map("/")        { run otto }
end

map("/app/")          { run Rack::File.new("#{PUBLIC_DIR}/app") }
map("/etc/")          { run Rack::File.new("#{PUBLIC_DIR}/etc") }
map("/img/")          { run Rack::File.new("#{PUBLIC_DIR}/img") }
