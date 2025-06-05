# apps/app_registry.rb

unless defined?(APPS_ROOT)
  project_root = ENV['ONETIME_HOME'] || File.expand_path("..", __dir__).freeze

  # Add the directory containing the rack applications to Ruby's load path
  APPS_ROOT = File.expand_path(project_root).freeze
  $LOAD_PATH.unshift(File.join(APPS_ROOT, 'api'))
  $LOAD_PATH.unshift(File.join(APPS_ROOT, 'web'))

  # Add the lib directoryfor require statements
  LIB_ROOT = File.join(project_root, 'lib').freeze
  $LOAD_PATH.unshift(LIB_ROOT)

  # Location for static web assets like images, CSS, and JavaScript files
  PUBLIC_DIR = File.join(project_root, '/public/web').freeze
end

require 'onetime'
require 'onetime/middleware'

module AppRegistry
  # Simple hash to store mount paths
  @applications = []
  @mounts = {}

  class << self
    attr_reader :applications, :mounts

    def track_application(app_class)
      @applications << app_class unless @applications.include?(app_class)
      OT.ld "AppRegistry tracking application: #{app_class}"
    end

    def initialize_applications
      discover_applications
      map_applications_to_routes
    end

    # Build rack application map
    def build
      mounts.transform_values { |app_class| app_class.new }
    end

    def discover_applications
      paths = Dir.glob(File.join(APPS_ROOT, '**/application.rb'))
      OT.ld "[app_registry] Found #{paths.join(', ')}"
      paths.each { |f| require f }
    end

    private

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

  end
end
