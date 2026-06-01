# apps/web/auth/spec/support/config_recreator.rb
#
# frozen_string_literal: true

module Auth
  # Recreates Auth::Config from scratch for test suites that need to
  # reconfigure with different feature flags. This is a last-resort pattern;
  # prefer RodauthTestHelper.create_rodauth_app for isolated feature testing.
  #
  # See: apps/web/auth/docs/auth-config-one-shot.md (Pattern 3)
  #
  module ConfigRecreator
    # Yields with a freshly-constructed Auth::Config class.
    #
    # Captures the current Auth::Config, removes it from the constant table,
    # builds a new one via the standard config.rb require path, then restores
    # the original after the block completes.
    #
    # @param env_overrides [Hash] ENV vars to set during reconstruction
    # @yield Block executed with the fresh Auth::Config in place
    #
    # WARNING: This invalidates all memoized references to Auth::Config
    # (Auth::Router's rodauth plugin, application registry entries, etc.).
    # Only use in isolated before(:all)/after(:all) blocks where the full
    # app is re-booted afterward.
    #
    def self.with_fresh_config(env_overrides: {})
      original_class = defined?(Auth::Config) ? Auth::Config : nil
      original_configured = original_class&.configured

      begin
        # Remove the existing constant if it exists
        Auth.send(:remove_const, :Config) if original_class

        # Apply env overrides
        saved_env = {}
        env_overrides.each do |key, value|
          saved_env[key] = ENV[key]
          ENV[key] = value
        end

        # Define a fresh Auth::Config class
        Auth.const_set(:Config, Class.new(Rodauth::Auth))
        Auth::Config.instance_variable_set(:@configured, false)

        class << Auth::Config
          attr_accessor :configured
        end

        # Reload the configuration file to populate the class with new env overrides
        load File.expand_path('../../config.rb', __dir__)

        yield Auth::Config
      ensure
        # Restore original class
        Auth.send(:remove_const, :Config) if defined?(Auth::Config)
        if original_class
          Auth.const_set(:Config, original_class)
          Auth::Config.instance_variable_set(:@configured, original_configured)
        end

        # Restore env
        saved_env&.each do |key, value|
          if value.nil?
            ENV.delete(key)
          else
            ENV[key] = value
          end
        end
      end
    end

    # Captures all AUTH_* environment variables. Use in before(:all) blocks
    # to snapshot env state before integration tests modify it.
    #
    # @return [Hash] captured env vars
    def self.capture_auth_env
      ENV.select { |k, _| k.start_with?('AUTH_') }.to_h
    end

    # Restores previously-captured AUTH_* environment variables, removing
    # any that were added during the test run.
    #
    # @param saved [Hash] previously captured env vars from capture_auth_env
    def self.restore_auth_env(saved)
      ENV.reject! { |k, _| k.start_with?('AUTH_') }
      saved&.each { |k, v| ENV[k] = v }
    end
  end
end
