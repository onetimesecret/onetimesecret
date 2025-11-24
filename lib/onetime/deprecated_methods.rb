# lib/onetime/deprecated_methods.rb
#
# frozen_string_literal: true

# Backwards compatibility accessors
#
# These methods delegate to Runtime state objects for existing code that
# expects direct module accessors (e.g., OT.global_secret, OT.i18n_enabled).
#
# This file exists to make it easy to remove deprecated methods in the future:
# simply delete this file and remove its require statement from lib/onetime.rb.
#
# Migration Guide:
# - OT.global_secret        -> OT::Runtime.security.global_secret
# - OT.rotated_secrets      -> OT::Runtime.security.rotated_secrets
# - OT.i18n_enabled         -> OT::Runtime.internationalization.enabled
# - OT.supported_locales    -> OT::Runtime.internationalization.supported_locales
# - OT.default_locale       -> OT::Runtime.internationalization.default_locale
# - OT.fallback_locale      -> OT::Runtime.internationalization.fallback_locale
# - OT.locales              -> OT::Runtime.internationalization.locales
# - OT.database_pool        -> OT::Runtime.infrastructure.database_pool
# - OT.d9s_enabled          -> OT::Runtime.infrastructure.d9s_enabled
# - OT.global_banner        -> OT::Runtime.features.global_banner
#
module Onetime
  # Security runtime state accessors
  def self.global_secret
    Runtime.security.global_secret
  end

  def self.rotated_secrets
    Runtime.security.rotated_secrets
  end

  # Internationalization runtime state accessors
  def self.i18n_enabled
    Runtime.internationalization.enabled
  end

  def self.supported_locales
    Runtime.internationalization.supported_locales
  end

  def self.default_locale
    Runtime.internationalization.default_locale
  end

  def self.fallback_locale
    Runtime.internationalization.fallback_locale
  end

  def self.locales
    Runtime.internationalization.locales
  end

  # Infrastructure runtime state accessors
  def self.database_pool
    Runtime.infrastructure.database_pool
  end

  def self.d9s_enabled
    Runtime.infrastructure.d9s_enabled
  end

  # Features runtime state accessors
  def self.global_banner
    Runtime.features.global_banner
  end
end
