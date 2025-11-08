# try/integration/middleware/detect_host_instances_try.rb
#
# frozen_string_literal: true

# These tryouts verify whether Rack instantiates a new middleware instance per
# request or reuses the same instance across requests using real Rack requests.

require_relative '../../support/test_helpers'

require 'stringio'
require 'middleware/detect_host'

# Create a global registry to track instances across tryouts
$instance_registry = []

class InstanceTrackingMiddleware < Rack::DetectHost
  def initialize(app, io: $stderr)
    super
    $instance_registry << self
  end
end

# Setup
@app = Rack::Builder.new do
  use InstanceTrackingMiddleware
  run lambda { |env| [200, {}, ['OK']] }
end.to_app

# Store the first instance in setup
@app.call({'HTTP_HOST' => 'example.com'})
@first_instance = $instance_registry.last

## Second request should use same instance
@app.call({'HTTP_HOST' => 'example2.com'})
[$instance_registry.size, $instance_registry.last.equal?(@first_instance)]
#=> [1, true]

## Multiple requests should still use same instance
5.times { |i| @app.call({'HTTP_HOST' => "example#{i}.com"}) }
[$instance_registry.size, $instance_registry.last.equal?(@first_instance)]
#=> [1, true]

## New app should create new middleware instance
@app2 = Rack::Builder.new do
  use InstanceTrackingMiddleware
  run lambda { |env| [200, {}, ['OK']] }
end.to_app
@app2.call({'HTTP_HOST' => 'example.com'})
[$instance_registry.size, $instance_registry.last.equal?(@first_instance)]
#=> [2, false]
