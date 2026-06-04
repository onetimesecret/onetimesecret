# lib/onetime/utils/config_resolver.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    # ConfigResolver provides test-aware configuration file resolution
    # with two-layer support: a defaults base file and an environment
    # override file.
    #
    # Layered resolution (all environments):
    #   Base:     etc/defaults/{name}.defaults.yaml (if present)
    #   Override: environment-specific file (see below)
    #
    # Override resolution order (test environment):
    #   1. spec/{name}.test.yaml
    #   2. apps/**/spec/{name}.test.yaml (first match)
    #   3. etc/{name}.yaml (fallback)
    #
    # Override resolution (non-test):
    #   - etc/{name}.yaml
    #
    # @example
    #   ConfigResolver.resolve('logging')
    #   # RACK_ENV=test  → spec/logging.test.yaml
    #   # RACK_ENV=dev   → etc/logging.yaml
    #
    #   ConfigResolver.resolve_stack('config')
    #   # RACK_ENV=test  → [etc/defaults/config.defaults.yaml, spec/config.test.yaml]
    #
    module ConfigResolver
      class << self
        # Resolve path to an environment-specific configuration file.
        #
        # @param name [String] Config name without extension (e.g., 'logging', 'auth')
        # @return [String, nil] Absolute path to config file, or nil if not found
        #
        def resolve(name)
          base = home_directory

          if test_environment?
            # 1. Check spec/{name}.test.yaml
            test_path = File.join(base, 'spec', "#{name}.test.yaml")
            if File.exist?(test_path)
              log_resolution(name, test_path, 'test')
              return test_path
            end

            # 2. Check apps/**/spec/{name}.test.yaml
            app_test_paths = Dir.glob(File.join(base, 'apps', '**', 'spec', "#{name}.test.yaml"))
            if app_test_paths.any?
              log_resolution(name, app_test_paths.first, 'app-test')
              return app_test_paths.first
            end
          end

          # Default: etc/{name}.yaml
          default_path = File.join(base, 'etc', "#{name}.yaml")
          if File.exist?(default_path)
            log_resolution(name, default_path, 'default')
            return default_path
          end

          log_resolution(name, nil, 'not found')
          nil
        end

        # Resolve path to the defaults base file.
        #
        # @param name [String] Config name without extension
        # @return [String, nil] Absolute path to defaults file, or nil if not found
        #
        def defaults_path(name)
          base = home_directory
          path = File.join(base, 'etc', 'defaults', "#{name}.defaults.yaml")

          if File.exist?(path)
            log_resolution(name, path, 'defaults')
            return path
          end

          log_resolution(name, nil, 'defaults not found')
          nil
        end

        # Resolve the full config stack: [defaults_path, override_path].
        # Either element may be nil.
        #
        # @param name [String] Config name without extension
        # @return [Array<String, nil>] Two-element array of [defaults, override]
        #
        def resolve_stack(name)
          [defaults_path(name), resolve(name)]
        end

        # @return [Boolean]
        def test_environment?
          ENV['RACK_ENV'] == 'test'
        end

        private

        def home_directory
          defined?(Onetime::HOME) ? Onetime::HOME : Dir.pwd
        end

        def log_resolution(name, path, source)
          return unless ENV['DEBUG_CONFIG_RESOLVER']

          if path
            warn "[ConfigResolver] #{name}: #{path} (#{source})"
          else
            warn "[ConfigResolver] #{name}: not found"
          end
        end
      end
    end
  end
end
