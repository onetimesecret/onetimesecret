# apps/app_registry.rb

unless defined?(APPS_ROOT)
  # Know where we are; use the project home directory if set or relative to us.
  project_root = ENV['ONETIME_HOME'] || File.expand_path("..", __dir__).freeze

  # Add each directory containing the rack applications to Ruby's load path.
  APPS_ROOT = File.join(project_root, 'apps').freeze
  %w{api web}.map { |name| $LOAD_PATH.unshift(File.join(APPS_ROOT, name)) }

  # Add the lib directory for the core project.
  LIB_ROOT = File.join(project_root, 'lib').freeze
  $LOAD_PATH.unshift(LIB_ROOT)

  # Define the directory for static web assets like images, CSS, and JS files.
  PUBLIC_DIR = File.join(project_root, '/public/web').freeze
end

require 'onetime'
require 'onetime/middleware'

module AppRegistry
  @application_classes = []
  @mount_mappings = {}

  class << self
    attr_reader :application_classes, :mount_mappings

    def register_application_class(app_class)
      @application_classes << app_class unless @application_classes.include?(app_class)
      OT.ld "[AppRegistry] Registered application: #{app_class}"
    end

    # Discover and map application classes to their respective routes
    def prepare_application_registry
      find_application_files
      create_mount_mappings
    rescue => e
      OT.le "[AppRegistry] ERROR: #{e.class}: #{e.message}"
      OT.ld e.backtrace.join("\n")

      Onetime.not_ready!
    end

    def generate_rack_url_map
      mappings = mount_mappings.transform_values { |app_class| app_class.new }
      Rack::URLMap.new(mappings)
    end

    private

    def find_application_files
      filepaths = Dir.glob(File.join(APPS_ROOT, '**/application.rb'))
      OT.ld "[AppRegistry] Scan found #{filepaths.size} application(s)"
      filepaths.each { |f| require f }
    end

    # Maps all discovered application classes to their URL routes
    # @return [Array<Class>] Registered application classes
    def create_mount_mappings
      OT.li "Mapping #{application_classes.size} application(s) to routes"

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
