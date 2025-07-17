# lib/onetime/configurator/environment_context.rb

module Onetime
  class Configurator
    # Provides a context for rendering YAML configuration templates with normalized
    # environment variables.
    #
    # This class prepares the environment before the main application configuration
    # is loaded, ensuring necessary variables are present and consistent for ERB
    # template rendering.
    #
    # @example Using the context to render a template
    #   require 'erb'
    #   context = Onetime::Configurator::EnvironmentContext.new
    #   template = ERB.new("RACK_ENV is <%= ENV['RACK_ENV'] %>")
    #   template.result(context.get_binding) #=> "RACK_ENV is production" (or development, etc.)
    #
    # @note This class normalizes environment variables for template rendering,
    #   and should not be confused with contexts used for running `init.d` or
    #   other system-level scripts.
    class EnvironmentContext
      # Initializes a new EnvironmentContext instance.
      #
      # Normalizes and freezes the provided environment hash.
      #
      # @param env [Hash<String, String>] The raw environment variables. Defaults to `ENV.to_h`.
      # @return [void]
      def initialize(env = ENV.to_h)
        @env = normalize_env_vars(env.dup).freeze
      end

      # Returns the normalized and frozen environment hash.
      #
      # @return [Hash<String, String>] The normalized environment variables.
      # @!method ENV
      def ENV = @env # rubocop:disable Naming/MethodName

      # Returns a `Binding` object for the current context.
      #
      # This binding can be used with `ERB` templates to allow them to access
      # the normalized environment variables via `ENV['VAR_NAME']`.
      #
      # @example
      #   erb_template = ERB.new("The environment is: <%= ENV['RACK_ENV'] %>")
      #   context = Onetime::Configurator::EnvironmentContext.new
      #   erb_template.result(context.get_binding)
      #
      # @return [Binding] A binding object suitable for ERB template rendering.
      def get_binding = binding

      private

      # Normalizes the given environment hash by applying various normalization rules.
      #
      # Applies all defined normalization routines to the input `env` hash, modifying it in place.
      #
      # @param env [Hash<String, String>] The environment hash to normalize.
      # @return [Hash<String, String>] The normalized environment hash (the same object passed in).
      # @private
      def normalize_env_vars(env)
        normalize_rack_vars!(env)
        normalize_regions_compatibility!(env)
        env
      end

      # Normalizes the `RACK_ENV` environment variable.
      #
      # Sets `RACK_ENV` to `Onetime.env` for consistency, as `Onetime.env` is determined
      # and normalized at application boot.
      #
      # @param env [Hash<String, String>] The environment hash to modify.
      # @return [void]
      # @private
      def normalize_rack_vars!(env)
        env['RACK_ENV'] = Onetime.env # the global env is normalized at boot
      end

      # Handles backward compatibility for region-related environment variables.
      #
      # In version `v0.20.6`, the environment variable `REGIONS_ENABLE` was renamed
      # to `REGIONS_ENABLED` for consistency. This method ensures that if either
      # `REGIONS_ENABLE` or `REGIONS_ENABLED` is present, the value is assigned
      # to `REGIONS_ENABLED`. If neither is present, `REGIONS_ENABLED` defaults
      # to 'false'.
      #
      # @param env [Hash<String, String>] The environment hash to modify.
      # @return [void]
      # @private
      def normalize_regions_compatibility!(env)
        set_value              = env['REGIONS_ENABLED'] || env['REGIONS_ENABLE'] || 'false'
        env['REGIONS_ENABLED'] = set_value
      end

      class << self
        # Returns a new binding object specifically for template rendering.
        #
        # This is a convenience class method that creates a new instance of
        # `EnvironmentContext` and immediately returns its binding.
        #
        # @return [Binding] A binding object suitable for ERB template rendering.
        def template_binding = new.get_binding
      end
    end
  end
end
