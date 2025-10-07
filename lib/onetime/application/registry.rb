# lib/onetime/application/registry.rb

module Onetime
  module Application
    # Application Registry
    #
    # Discovers and manages Rack applications for URL mapping
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
          OT.le "[Application::Registry] ERROR: #{ex.class}: #{ex.message}"
          OT.ld ex.backtrace.join("\n")

          Onetime.not_ready!
        end

        def generate_rack_url_map
          mappings = mount_mappings.transform_values { |app_class| app_class.new }
          Rack::URLMap.new(mappings)
        end

        private

        def find_application_files
          apps_root = File.join(ENV['ONETIME_HOME'] || File.expand_path('../../..', __dir__), 'apps')
          filepaths = Dir.glob(File.join(apps_root, '**/application.rb'))
          OT.ld "[registry] Scan found #{filepaths.size} application(s)"
          filepaths.each { |f| require f }
        end

        # Maps all discovered application classes to their URL routes
        # @return [Array<Class>] Registered application classes
        def create_mount_mappings
          OT.li "[registry] Mapping #{application_classes.size} application(s) to routes"

          application_classes.each do |app_class|
            mount = app_class.uri_prefix

            unless mount.is_a?(String)
              raise ArgumentError, "Mount point must be a string (#{app_class} gave #{mount.class})"
            end

            OT.li "  #{app_class} for #{mount}"
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
