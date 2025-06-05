# apps/app_registry.rb

APPS_ROOT = File.expand_path(__dir__).freeze
$LOAD_PATH.unshift(File.join(APPS_ROOT, 'api'))
$LOAD_PATH.unshift(File.join(APPS_ROOT, 'web'))

module AppRegistry
  # Simple hash to store mount paths
  @applications = []
  @mounts = {}

  class << self
    attr_reader :applications, :mounts

    def discover_applications
      paths = Dir.glob(File.join(APPS_ROOT, '**/application.rb'))
      OT.ld "[app_registry] Found #{paths.join(', ')}"
      paths.each { |f| require f }
    end

    def track_application(app_class)
      @applications << app_class unless @applications.include?(app_class)
      OT.ld "AppRegistry tracking application: #{app_class}"
    end

    # Maps all discovered application classes to their URL routes
    # @return [Array<Class>] Registered application classes
    def map_applications_to_routes
      OT.li "Mapping #{applications.size} application(s) to routes"

      applications.each do |app_class|
        mount = app_class.uri_prefix

        unless mount.is_a?(String)
          raise ArgumentError, "Mount point must be a string (#{app_class} gave #{mount.class})"
        end

        OT.li "  #{app_class} for #{mount}"
        register(mount, app_class)
      end

      applications
    end

    # Register an application with its mount path
    def register(path, app_class)
      @mounts[path] = app_class
    end

    # Build rack application map
    def build
      mounts.transform_values { |app_class| app_class.new }
    end

    # Generate path to a registered app
    def path_to(mount_path, path = '/')
      path = path.start_with?('/') ? path : "/#{path}"
      "#{mount_path}#{path}"
    end
  end
end
