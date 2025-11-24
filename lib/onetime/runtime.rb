# lib/onetime/runtime.rb
#
# frozen_string_literal: true

# Runtime state management for Onetime
#
# This module provides domain-separated, immutable state storage for values
# computed and set during application initialization. This is distinct from
# configuration (which is loaded from YAML files) - runtime state is derived
# from configuration, environment variables, and initialization logic.
#
# Architecture:
# - Each domain (Security, Localization, etc.) is a Ruby Data class
# - Data classes are immutable by design (thread-safe reads)
# - State is set once during boot by initializers
# - Backwards compatibility provided via Onetime module accessors
#
# Usage:
#   # Direct access (preferred)
#   Onetime::Runtime.security.global_secret
#   Onetime::Runtime.localization.enabled
#
#   # Backwards compatibility (maintained for existing code)
#   Onetime.global_secret  # → Runtime.security.global_secret
#   Onetime.i18n_enabled   # → Runtime.localization.enabled
#
module Onetime
  module Runtime
    # Load domain Data classes
    require_relative 'runtime/security'
    require_relative 'runtime/internationalization'
    require_relative 'runtime/infrastructure'
    require_relative 'runtime/features'
    require_relative 'runtime/email'

    # Initialize domain state with defaults
    @security = Security.default
    @internationalization = Internationalization.default
    @infrastructure = Infrastructure.default
    @features = Features.default
    @email = Email.default

    class << self
      # Domain state accessors (read-only)
      attr_reader :security, :internationalization, :infrastructure, :features, :email

      # Replace entire domain state (immutable update pattern)
      #
      # These methods are used by initializers to set runtime state during boot.
      # Each accepts a new Data object and freezes it to prevent modification.
      #
      # @param new_state [Data] New domain state object
      # @return [Data] The frozen state object
      #
      def security=(new_state)
        @security = new_state.freeze
      end

      def internationalization=(new_state)
        @internationalization = new_state.freeze
      end

      def infrastructure=(new_state)
        @infrastructure = new_state.freeze
      end

      def features=(new_state)
        @features = new_state.freeze
      end

      def email=(new_state)
        @email = new_state.freeze
      end

      # Convenience: update domain with partial changes (merge pattern)
      #
      # These methods create a new Data object by merging changes into the
      # existing state. Useful when an initializer only needs to update
      # specific fields without replacing the entire domain.
      #
      # @param changes [Hash] Fields to update
      # @return [Data] The new frozen state object
      #
      # @example
      #   Runtime.update_security(global_secret: ENV['SECRET'])
      #
      def update_security(**changes)
        self.security = Security.new(**@security.to_h.merge(changes))
      end

      def update_internationalization(**changes)
        self.internationalization = Internationalization.new(**@internationalization.to_h.merge(changes))
      end

      def update_infrastructure(**changes)
        self.infrastructure = Infrastructure.new(**@infrastructure.to_h.merge(changes))
      end

      def update_features(**changes)
        self.features = Features.new(**@features.to_h.merge(changes))
      end

      def update_email(**changes)
        self.email = Email.new(**@email.to_h.merge(changes))
      end

      # Reset all runtime state to defaults (primarily for testing)
      #
      # @return [void]
      #
      def reset!
        @security = Security.default
        @internationalization = Internationalization.default
        @infrastructure = Infrastructure.default
        @features = Features.default
        @email = Email.default
        nil
      end

      # Inspect runtime state for debugging
      #
      # @return [Hash] All domain state as hashes
      #
      def to_h
        {
          security: @security.to_h,
          internationalization: @internationalization.to_h,
          infrastructure: @infrastructure.to_h,
          features: @features.to_h,
          email: @email.to_h,
        }
      end
    end
  end
end
