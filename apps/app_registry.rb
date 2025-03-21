# apps/app_registry.rb

module AppRegistry
  # Simple hash to store mount paths
  @mounts = {}

  class << self
    attr_reader :mounts

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
