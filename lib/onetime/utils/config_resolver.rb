# lib/onetime/utils/config_resolver.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    # ConfigResolver provides test-aware configuration file resolution.
    #
    # Ensures proper test isolation by automatically using test-specific
    # config files from spec/ when RACK_ENV=test.
    #
    # Resolution order (test environment):
    #   1. spec/{name}.test.yaml
    #   2. apps/**/spec/{name}.test.yaml (first match)
    #   3. etc/{name}.yaml (fallback)
    #
    # Resolution (non-test):
    #   - etc/{name}.yaml
    #
    # @example
    #   ConfigResolver.resolve('logging')
    #   # RACK_ENV=test  → spec/logging.test.yaml
    #   # RACK_ENV=dev   → etc/logging.yaml
    #
    #   ConfigResolver.resolve('billing')
    #   # RACK_ENV=test  → apps/web/billing/spec/billing.test.yaml
    #
    module ConfigResolver
      class << self
        # Resolve path to a configuration file.
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
