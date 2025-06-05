# apps/base_application.rb

require 'rack'
require 'otto'
require 'json'

require_relative 'app_registry'
require_relative 'middleware_stack'

class BaseApplication
  attr_reader :options, :router, :rack_app

  def initialize(options = {})
    @options = options
    @router = build_router
    @rack_app = build_rack_app
  end

  def call(env)
    rack_app.call(env)
  end

  private

  def build_router
    raise NotImplementedError
  end

  def build_rack_app
    # Capture router reference in local variable for block access
    # Rack::Builder uses `instance_eval` internally, creating a new context
    # so inside of it `self` refers to the Rack::Builder instance.
    router_instance = router

    # Invoke the warmup block if it is defined
    self.class.warmup&.call
    Rack::Builder.new do |builder|
      MiddlewareStack.configure(builder)

      self.class.middleware.each do |middleware, args, block|
        builder.use(middleware, *args, &block)
      end

      run router_instance
    end.to_app
  end

  class << self
    @uri_prefix = nil
    @middleware = nil

    attr_reader :uri_prefix, :middleware

    # Tracks subclasses for deferred registration
    # @param subclass [Class] The class inheriting from BaseApplication
    # @return [void]
    def inherited(subclass)
      # Keep track subclasses without immediate registration
      AppRegistry.track_application(subclass)
      OT.ld "BaseApplication.inherited: #{subclass} registered with AppRegistry"
    end

    def use(klass, *args, &block)
      @middleware ||= []
      @middleware << [klass, args, block]
    end

    def warmup(&block)
      @warmup_block = block if block_given?
      @warmup_block
    end
  end
end
