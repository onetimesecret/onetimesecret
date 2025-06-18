# lib/onetime/services/legacy_globals.rb

require 'onetime/refinements/indifferent_hash_access'

module Onetime
  module Services
    # LegacyGlobals
    #
    # A temporary solution to ease the transition to the modular service
    # provider architecture.
    #
    # Previously available as global methods (e.g. OT.d9s_enabled).
    #
    # NOTE: We intentionally use OT.conf here and not direct to the system
    # state so that we're not circumventing Boot.boot! initialization steps.
    module LegacyGlobals
      using IndifferentHashAccess

      def global_secret
        LegacyGlobals.print_warning
        @global_secret ||= OT.conf&.dig('site', 'secret')
      end

      def d9s_enabled
        LegacyGlobals.print_warning
        @d9s_enabled ||= OT.conf&.dig('diagnostics', 'enabled')
      end

      def locales
        LegacyGlobals.print_warning
        @locales ||= OT.conf&.fetch('locales', {})
      end

      def default_locale
        LegacyGlobals.print_warning
        @default_locale ||= OT.conf&.dig('i18n', 'default_locale')
      end

      def fallback_locale
        LegacyGlobals.print_warning
        @fallback_locale ||= OT.conf&.dig('i18n', 'fallback_locale')
      end

      def supported_locales
        LegacyGlobals.print_warning
        @supported_locales ||= OT.conf&.fetch('supported_locales')
      end

      def i18n_enabled
        LegacyGlobals.print_warning
        @i18n_enabled ||= OT.conf&.dig('i18n', 'enabled')
      end

      def global_banner
        LegacyGlobals.print_warning
        @global_banner ||= OT.conf&.fetch('global_banner', nil)
      end

      def emailer
        LegacyGlobals.print_warning
        @emailer ||= OT.conf&.fetch('emailer', nil)
      end

      def self.print_warning
        code_path = caller(3..3).first
        OT.lw "[LEGACY] Global method call from #{code_path}"
      end
    end
  end

  # Here we self-extend the Onetime namespace which provides access to the
  # legacy global attributes and simplifies the cleanup since the only
  # integration point is the require statement.
  extend Services::LegacyGlobals
end
