# lib/onetime/application/registry.rb

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

      class << self
        attr_reader :application_classes, :mount_mappings

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

          mappings = sorted_mappings.transform_values do |app_class|
            warmup_counter += 1
            # Pass warmup context to application initialization
            Thread.current[:warmup_context] = { current: warmup_counter, total: total_apps }
            app_class.new
          end

          Rack::URLMap.new(mappings)
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

          # Re-register classes that are already loaded in memory
          reregister_loaded_applications
        end

        # Re-register application classes that are already in memory
        def reregister_loaded_applications
          # Check for Core app
          if defined?(Core::Application)
            register_application_class(Core::Application)
          end

          # Check for V2 API app
          if defined?(V2::Application)
            register_application_class(V2::Application)
          end

          # Check for V3 API app
          if defined?(V3::Application)
            register_application_class(V3::Application)
          end

          # Check for Account API app
          if defined?(AccountAPI::Application)
            register_application_class(AccountAPI::Application)
          end

          # Only re-register Auth app if advanced mode
          if defined?(Auth::Application) && Onetime.auth_config.mode == 'advanced'
            register_application_class(Auth::Application)
          end
        end

        private

        def find_application_files
          apps_root = File.join(ENV['ONETIME_HOME'] || File.expand_path('../../..', __dir__), 'apps')
          filepaths = Dir.glob(File.join(apps_root, '**/application.rb'))

          # Skip auth app in basic mode - auth endpoints handled by Core Web App
          if Onetime.auth_config.mode == 'basic'
            filepaths.reject! { |f| f.include?('web/auth/') }

            Onetime.log_box(
              ['AUTH MODE: Basic (Core handles /auth/*)'],
            )
          else
            Onetime.log_box(
              ['AUTH MODE: Advanced (Rodauth enabled)'],
            )
          end

          Onetime.app_logger.info "[registry] Scan found #{filepaths.size} application(s)"

          filepaths.each_with_index do |f, idx|
            pretty_path = Onetime::Utils.pretty_path(f)
            Onetime.app_logger.info "[registry] [#{idx + 1} of #{filepaths.size}] Loading: #{pretty_path}" if Onetime.debug?
            begin
              require f
            rescue LoadError => ex
              Onetime.app_logger.info "
"
              Onetime.log_box(
                [
                  '❌ APPLICATION LOAD FAILED',
                  "   >> #{pretty_path} <<"
                ],
                level: :error
              )
              Onetime.app_logger.info "
"
              raise ex
            end
          end
        end

        # Maps all discovered application classes to their URL routes
        # @return [Array<Class>] Registered application classes
        def create_mount_mappings
          OT.li "[registry] Mapping #{application_classes.size} application(s) to routes"

          application_classes.each_with_index do |app_class, idx|
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
