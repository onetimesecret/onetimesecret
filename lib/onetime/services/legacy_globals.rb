# lib/onetime/services/legacy_globals.rb

require 'onetime/refinements/indifferent_hash_access'

module Onetime
  module Services
    # LegacyGlobals
    #
    # A temporary solution to ease the transition to the modular service
    # provider architecture.
    #
    # Previously available globals (e.g. OT.d9s_enabled):
    # :d9s_enabled, :i18n_enabled, :locales,
    # :supported_locales, :default_locale, :fallback_locale, :global_banner,
    # :rotated_secrets, :emailer, :first_boot, :global_secret
    #
    module LegacyGlobals
      using IndifferentHashAccess

      def d9s_enabled
        @d9s_enabled ||= OT.conf[:diagnostics][:enabled]
      end

      def locales
        @locales ||= OT.conf[:i18n][:locales]
      end

      def default_locale
        @default_locale ||= OT.conf[:i18n][:default_locale]
      end

      def fallback_locale
        @fallback_locale ||= OT.conf[:i18n][:fallback_locale]
      end

      def supported_locales
        @supported_locales ||= OT.conf[:i18n][:supported_locales]
      end

      def i18n_enabled
        @i18n_enabled ||= OT.conf[:i18n][:enabled]
      end

      def global_banner
        @global_banner ||= OT.conf[:global_banner]
      end

    end
  end

  # Here we self-extend the Onetime namespace which provides access to the
  # legacy global attributes and simplifies the cleanup since the only
  # integration point is the require statement.
  extend Services::LegacyGlobals
end
