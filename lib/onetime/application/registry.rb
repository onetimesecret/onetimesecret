# lib/onetime/application/registry.rb
#
# frozen_string_literal: true

module Onetime
  module Application
    # Application Registry
    #
    # Discovers and manages Rack applications for URL mapping.
    #
    # Mount order must be handled carefully to resolve endpoint conflicts:
    # - Auth app (when enabled) should take over auth endpoints from the core web app
    # - More specific paths are mounted before general ones to avoid shadowing
    # - Rack uses "first match wins" principle based on mounting order
    # - Applications are processed sequentially in config.ru order
    #
    module Registry
      # These class instance vars are populated at start-time and then readonly.
      # rubocop:disable ThreadSafety/MutableClassInstanceVariable
      @application_classes = []
      @mount_mappings      = {}
      @application_instances = {}

      class << self
        attr_reader :application_classes, :mount_mappings, :application_instances

        def register_application_class(app_class)
          @application_classes << app_class unless @application_classes.include?(app_class)
          OT.ld "[registry] Registered application: #{app_class}"
        end

        # Discover and map application classes to their respective routes
        def prepare_application_registry
          find_application_files
          create_mount_mappings
        rescue StandardError => ex
          Onetime.app_logger.info "[#{name}] ERROR: #{ex.class}: #{ex.message}"
          Onetime.app_logger.info ex.backtrace.join("\n") if Onetime.debug?

          Onetime.not_ready
        end

        # Generate Rack::URLMap with proper mount ordering
        #
        # Applications are ordered to ensure proper endpoint resolution:
        # 1. More specific paths first to avoid being shadowed by general ones
        # 2. Auth app (when present) mounted before core web app to take over auth endpoints
        # 3. Rack processes mounts sequentially using "first match wins"
        def generate_rack_url_map
          # Sort mappings by path specificity (longer/more specific paths first)
          sorted_mappings = mount_mappings.sort_by { |path, _| [-path.length, path] }.to_h

          # Track warmup progress for [N of M] numbering
          total_apps = sorted_mappings.size
          warmup_counter = 0

          mappings = sorted_mappings.transform_values do |app_class, path|
            warmup_counter += 1
            # Pass warmup context to application initialization
            Thread.current[:warmup_context] = { current: warmup_counter, total: total_apps }
            instance = app_class.new
            # Store instance for health checks
            @application_instances[app_class] = instance
            instance
          end

          Rack::URLMap.new(mappings)
        end

        # Check health of all registered applications
        #
        # Aggregates initialization health status from all instantiated
        # applications. Returns false if any application failed to initialize.
        #
        # NOTE: This checks initialization success only. See Base#healthy? for
        # details on scope and limitations of health checking across different
        # router types (Otto, Roda, etc.).
        #
        # @return [Hash] Aggregated health status with per-application details
        def health_check
          results = {
            healthy: true,
            applications: {}
          }

          application_instances.each do |app_class, instance|
            health = instance.health_check
            results[:applications][app_class.name] = health
            results[:healthy] = false unless health[:healthy]
          end

          results
        end

        # Check if all applications are healthy
        #
        # Convenience method that returns boolean health status across all
        # registered applications. Equivalent to `health_check[:healthy]`.
        #
        # @return [Boolean] true if all apps initialized successfully
        def healthy?
          health_check[:healthy]
        end

        # Reset registry state (for testing and development)
        #
        # Clears all mappings and classes, then re-registers any classes
        # that are already loaded in memory. This is necessary because Ruby's
        # require is idempotent - once a file is loaded, subsequent requires
        # do nothing.
        #
        # In production, this is called during boot. In tests, it's called
        # between test runs to ensure clean state.
        def reset!
          @mount_mappings = {}
          @application_classes = []
          @application_instances = {}

          # Re-register classes that are already loaded in memory
          reregister_loaded_applications
        end

        # Re-register application classes that are already in memory
        def reregister_loaded_applications
          ObjectSpace.each_object(Class)
            .select { |cls| cls < Onetime::Application::Base && cls.respond_to?(:uri_prefix) }
            .reject { |cls| cls.name == 'Auth::Application' && Onetime.auth_config.mode != 'advanced' }
            .reject { |cls| cls.instance_variable_get(:@abstract) == true } # Skip abstract base classes
            .each { |cls| register_application_class(cls) }
        end

        private

        def find_application_files
          apps_root = File.join(ENV['ONETIME_HOME'] || File.expand_path('../../..', __dir__), 'apps')
          filepaths = Dir.glob(File.join(apps_root, '**/application.rb'))

          # Skip auth app in basic mode - auth endpoints handled by Core Web App
          if Onetime.auth_config.mode == 'basic'
            filepaths.reject! { |f| f.include?('web/auth/') }
          end

          Onetime.app_logger.info "[registry] Scan found #{filepaths.size} application(s)"

          # Log auth mode after scan but before loading
          auth_mode_msg = if Onetime.auth_config.mode == 'basic'
              'Basic (Core handles /auth/*)'
          else
            'Advanced (Rodauth enabled)'
          end

          Onetime.log_box(
            ["AUTHENTICATION MODE: #{auth_mode_msg}"],
            logger_method: :auth_logger
          )

          filepaths.each_with_index do |f, idx|
            pretty_path = Onetime::Utils.pretty_path(f)
            Onetime.app_logger.info "[registry] [#{idx + 1} of #{filepaths.size}] Loading: #{pretty_path}" if Onetime.debug?
            begin
              require f
            rescue LoadError => ex
              Onetime.app_logger.info "\n"
              Onetime.log_box(
                [
                  '❌ APPLICATION LOAD FAILED',
                  "   >> #{pretty_path} <<"
                ],
                level: :error
              )
              Onetime.app_logger.info "\n"
              raise ex
            end
          end
        end

        # Maps all discovered application classes to their URL routes
        # @return [Array<Class>] Registered application classes
        def create_mount_mappings
          OT.li "[registry] Mapping #{application_classes.size} application(s) to routes"

          application_classes.each_with_index do |app_class, idx|
            # Skip abstract base classes
            if app_class.instance_variable_get(:@abstract) == true
              Onetime.app_logger.debug " [#{idx + 1} of #{application_classes.size}] Skipping abstract class #{app_class}"
              next
            end

            mount = app_class.uri_prefix

            unless mount.is_a?(String)
              raise ArgumentError, "Mount point must be a string (#{app_class} gave #{mount.class})"
            end

            Onetime.app_logger.debug " [#{idx + 1} of #{application_classes.size}] Registering #{app_class} at #{mount}"

            register(mount, app_class)
          end

          application_classes
        end

        # Register an application with its mount path
        def register(path, app_class)
          @mount_mappings[path] = app_class
        end

      end
    end
  end
end
