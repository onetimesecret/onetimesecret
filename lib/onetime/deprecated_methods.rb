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
# - OT.i18n_enabled         -> OT::Runtime.internationalization.enabled
# - OT.supported_locales    -> OT::Runtime.internationalization.supported_locales
# - OT.default_locale       -> OT::Runtime.internationalization.default_locale
# - OT.fallback_locale      -> OT::Runtime.internationalization.fallback_locale
# - OT.locales              -> OT::Runtime.internationalization.locales
# - OT.database_pool        -> OT::Runtime.infrastructure.database_pool
# - OT.d9s_enabled          -> OT::Runtime.infrastructure.d9s_enabled
# - OT.global_banner        -> OT::Runtime.features.global_banner
# - OT.global_banner_scope  -> OT::Runtime.features.global_banner_scope
#
module Onetime
  # Security runtime state accessors
  def self.global_secret
    Runtime.security.global_secret
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

  def self.date_format
    Runtime.internationalization.date_format
  end

  def self.datetime_format
    Runtime.internationalization.datetime_format
  end

  # Infrastructure runtime state accessors
  def self.database_pool
    Runtime.infrastructure.database_pool
  end

  def self.d9s_enabled
    Runtime.infrastructure.d9s_enabled
  end

  def self.d9s_enabled=(value)
    Runtime.update_infrastructure(d9s_enabled: value)
  end

  # Features runtime state accessors
  #
  # Banner reads go through a TTL-bounded re-read (BannerState.refresh_if_stale!)
  # so a banner published or cleared by ANOTHER process (Puma worker, container,
  # CLI) becomes visible here within BannerState::CACHE_TTL seconds — the
  # runtime state alone is only refreshed at boot and by the process that
  # handled the write. All cache state lives in lib/onetime/operations/banner.rb;
  # these stay one-line delegates.
  #
  # The `defined?` guard keeps the ops require lazy (the CheckGlobalBanner
  # initializer loads it; a top-level require here would recreate the boot-time
  # require cycle documented in runtime/features.rb) and keeps unbooted unit
  # specs on the plain runtime default.
  def self.global_banner
    Operations::BannerState.refresh_if_stale! if defined?(Onetime::Operations::BannerState)
    Runtime.features.global_banner
  end

  def self.global_banner_scope
    Operations::BannerState.refresh_if_stale! if defined?(Onetime::Operations::BannerState)
    Runtime.features.global_banner_scope
  end
end
