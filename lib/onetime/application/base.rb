# lib/onetime/application/base.rb
#
# frozen_string_literal: true

require 'rack'
require 'familia/json_serializer'
require_relative '../logger_methods'

module Onetime
  module Application
    # Base Application Class
    #
    # Foundation for all Onetime Rack applications. Provides a consistent
    # initialization pattern that separates universal middleware from
    # router-specific configuration.
    #
    # ## Architecture
    #
    # Applications built on this base follow a layered approach:
    #
    # 1. **Universal Middleware** (MiddlewareStack)
    #    - Framework-agnostic components (sessions, CSRF, logging)
    #    - Applied to ALL applications regardless of router
    #
    # 2. **Application-Specific Middleware** (via class `use` calls)
    #    - Configured declaratively at class level
    #    - Examples: Core::Middleware::RequestSetup, error handling
    #
    # 3. **Router Instance** (via `build_router`)
    #    - Otto, Roda, or other Rack-compatible router
    #    - Router-specific configuration happens HERE
    #    - Otto apps should include `OttoHooks` module
    #
    # ## Subclass Responsibilities
    #
    # When creating a new application:
    #
    # 1. Set `@uri_prefix` class variable (e.g., '/api/v2', '/auth')
    # 2. Declare app-specific middleware using `use` at class level
    # 3. Implement `build_router` to create and configure router instance
    # 4. For Otto routers: include `Onetime::Application::OttoHooks`
    #
    # @example Otto-based application
    #   class Application < Onetime::Application::Base
    #     include Onetime::Application::OttoHooks
    #
    #     @uri_prefix = '/api/v2'.freeze
    #     use MyApp::Middleware::CustomHandler
    #
    #     protected
    #
    #     def build_router
    #       router = Otto.new(routes_path)
    #       configure_otto_request_hook(router)  # from OttoHooks
    #       router.enable_full_ip_privacy!
    #       router
    #     end
    #   end
    #
    # @example Roda-based application
    #   class Application < Onetime::Application::Base
    #     @uri_prefix = '/auth'.freeze
    #
    #     protected
    #
    #     def build_router
    #       MyApp::Router  # Roda class responds to #call
    #     end
    #   end
    #
    class Base
      include Onetime::LoggerMethods

      attr_reader :options, :router, :rack_app

      def initialize(options = {})
        app_logger.debug 'Initializing', {
          application: self.class.name,
          options: options,
        }
        @options  = options

        app_logger.debug 'Building router', {
          application: self.class.name,
        }
        @router   = build_router

        app_logger.debug 'Building rack app', {
          application: self.class.name,
        }
        @rack_app = build_rack_app
      end

      def call(env)
        rack_app.call(env)
      end

      # Health check for application initialization
      #
      # Verifies that the application successfully completed initialization by
      # checking that both router and rack_app were constructed without errors.
      #
      # SCOPE: This checks initialization success only, not runtime correctness.
      #
      # What this catches:
      # - Router construction failures (file not found, syntax errors)
      # - Rack app build failures (middleware errors, configuration issues)
      #
      # What this intentionally doesn't catch:
      # - Route handler errors (Otto/Roda use lazy evaluation)
      # - Missing classes referenced in routes (caught at request time)
      # - Logic errors in handler classes (runtime concern)
      #
      # Rationale: Both Otto and Roda use lazy evaluation for route handlers.
      # Attempting to validate all route handlers would require executing code
      # with potential side effects, fighting framework design. Runtime errors
      # should be caught by monitoring and logging systems, not health checks.
      #
      # @return [Boolean] true if initialization succeeded, false otherwise
      def healthy?
        !router.nil? && !rack_app.nil?
      end

      # Get detailed health check information
      #
      # Returns structured health data suitable for boot validation and
      # monitoring systems. See #healthy? for scope and limitations.
      #
      # @return [Hash] Health status with initialization details
      def health_check
        {
          application: self.class.name,
          healthy: healthy?,
          router_present: !router.nil?,
          rack_app_present: !rack_app.nil?,
        }
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
          name: base_klass.name,
          prefix: base_klass.uri_prefix,
        }

        Rack::Builder.new do |builder|
          MiddlewareStack.configure(builder, application_context: app_context)

          (base_klass.middleware || []).each do |middleware, args, block|
            builder.use(middleware, *args, &block)
          end

          # Wrap the warmup to log before and after actual execution
          if base_klass.warmup
            builder.warmup do |built_app|
              Onetime.app_logger.debug 'Warmup started', {
                application: app_context[:name],
              }

              # Call the actual warmup block
              base_klass.warmup.call(built_app)

              # Log completion AFTER warmup finishes
              message = "WARMED UP #{base_klass} at #{base_klass.uri_prefix}"

              # Use log_box helper for consistent formatting
              Onetime.log_box([message], logger_method: :app_logger, level: :debug) # reduce noise at 'info'
            end
          end

          builder.run router_instance
        end.to_app
      end

      class << self
        @uri_prefix = nil
        @middleware = nil

        attr_reader :uri_prefix, :middleware

        # Determine if this application should skip loading
        # Override in subclasses to implement conditional loading logic
        # @return [Boolean] true if application should not be loaded
        def should_skip_loading?
          false
        end

        # Tracks subclasses for deferred registration
        # @param subclass [Class] The class inheriting from Onetime::Application::Base
        # @return [void]
        def inherited(subclass)
          # Keep track subclasses without immediate registration
          Registry.register_application_class(subclass)
          Onetime.app_logger.debug 'Application registered', {
            application: subclass.name,
          }
        end

        def use(klass, *args, &block)
          @middleware ||= []
          @middleware << [klass, args, block]
        end

        def warmup(&block)
          @warmup_block = block if block_given?
          @warmup_block
        end

        # DSL for registering inline initializers
        #
        # Creates an anonymous Initializer subclass and registers it with the
        # InitializerRegistry. This provides a convenient syntax for app-specific
        # boot initializers without requiring separate files.
        #
        # @param name [Symbol] Initializer name
        # @param options [Hash] Configuration options
        # @option options [Array<Symbol>] :depends_on Capability dependencies
        # @option options [Array<Symbol>] :provides Capabilities this provides
        # @option options [Boolean] :optional If true, failure won't halt boot
        # @option options [String] :description Human-readable description
        # @yield [ctx] Initializer code block
        # @yieldparam ctx [Hash] Shared context across initializers
        #
        # @example
        #   class MyApp < Onetime::Application::Base
        #     initializer :setup_feature, provides: [:feature] do |ctx|
        #       # initialization code
        #     end
        #   end
        def initializer(name, **options, &block)
          raise ArgumentError, 'Block required for initializer' unless block_given?

          # Capture application class in closure
          app_class = self

          # Create anonymous initializer class
          klass = Class.new(Onetime::Boot::Initializer) do
            @initializer_name  = name
            @application_class = app_class
            @depends_on        = Array(options[:depends_on])
            @provides          = Array(options[:provides])
            @optional          = options.fetch(:optional, false)
            @description_text  = options.fetch(:description, nil)
            @init_block        = block

            class << self
              attr_reader :initializer_name, :application_class, :depends_on,
                :provides, :optional, :description_text, :init_block
            end

            # Override description if provided
            def description
              self.class.description_text || super
            end

            # Override application_class accessor to return the stored class
            def application_class
              self.class.application_class
            end

            # Instance method to execute the block
            def execute(ctx)
              instance_exec(ctx, &self.class.init_block)
            end
          end

          # Pure DI: Register with current registry if set (for tests)
          # In production, ObjectSpace discovery finds all initializer classes
          current = Onetime::Boot::InitializerRegistry.current
          current&.register_class(klass)

          klass
        end
      end
    end
  end
end
