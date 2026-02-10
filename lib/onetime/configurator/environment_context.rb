# lib/onetime/configurator/environment_context.rb
#
# frozen_string_literal: true

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
    #   template.result(context.get_binding) #=> "RACK_ENV is production"
    #
    # Creates a self-contained environment context without affecting global ENV.
    class EnvironmentContext
      def initialize(env = ENV.to_h)
        @env = normalize_env_vars(env.dup).freeze
      end

      # Returns the normalized and frozen environment hash.
      def ENV = @env # rubocop:disable Naming/MethodName

      # Returns a Binding object for ERB template rendering.
      def get_binding = binding

      private

      def normalize_env_vars(env)
        normalize_rack_vars!(env)
        normalize_regions_compatibility!(env)
        env
      end

      # Sets RACK_ENV to Onetime.env for consistency
      def normalize_rack_vars!(env)
        env['RACK_ENV'] = Onetime.env
      end

      # In v0.20.6, REGIONS_ENABLE was renamed to REGIONS_ENABLED.
      # This ensures backward compatibility.
      def normalize_regions_compatibility!(env)
        set_value              = env['REGIONS_ENABLED'] || env['REGIONS_ENABLE'] || 'false'
        env['REGIONS_ENABLED'] = set_value
      end

      class << self
        def template_binding = new.get_binding
      end
    end
  end
end
