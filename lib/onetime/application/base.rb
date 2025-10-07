# lib/onetime/application/base.rb

require 'rack'
require 'otto'
require 'familia/json_serializer'

module Onetime
  module Application
    class Base
      attr_reader :options, :router, :rack_app

      def initialize(options = {})
        @options  = options
        @router   = build_router
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
        @middleware   ||= []
        base_klass      = self.class

        # Create application context for middleware before the builder block
        app_context = {
          name: base_klass.name.split('::').last.downcase,
          prefix: base_klass.uri_prefix,
          type: determine_app_type(base_klass)
        }

        Rack::Builder.new do |builder|
          MiddlewareStack.configure(builder, application_context: app_context)

          (base_klass.middleware || []).each do |middleware, args, block|
            builder.use(middleware, *args, &block)
          end

          # Invoke the warmup block if it is defined
          builder.warmup(&base_klass.warmup) # TODO: Or builder.warmup&.call?

          builder.run router_instance
        end.to_app
      end

      def determine_app_type(app_class)
        case app_class.name
        when /Core::Application/ then :web
        when /V2::Application/   then :api
        when /Auth::/            then :auth
        else :unknown
        end
      end

      class << self
        @uri_prefix = nil
        @middleware = nil

        attr_reader :uri_prefix, :middleware

        # Tracks subclasses for deferred registration
        # @param subclass [Class] The class inheriting from Onetime::Application::Base
        # @return [void]
        def inherited(subclass)
          # Keep track subclasses without immediate registration
          Registry.register_application_class(subclass)
          OT.ld "[Application::Base.inherited] #{subclass} registered"
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
  end
end
