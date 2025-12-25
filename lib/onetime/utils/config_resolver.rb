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
    # Resolution:
    #   - RACK_ENV=test: spec/{name}.test.yaml (falls back to etc/{name}.yaml)
    #   - Otherwise: etc/{name}.yaml
    #
    # @example
    #   ConfigResolver.resolve('logging')
    #   # RACK_ENV=test  → spec/logging.test.yaml
    #   # RACK_ENV=dev   → etc/logging.yaml
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

          # Test environment: use spec/{name}.test.yaml
          if test_environment?
            test_path = File.join(base, 'spec', "#{name}.test.yaml")
            if File.exist?(test_path)
              log_resolution(name, test_path, 'test')
              return test_path
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
