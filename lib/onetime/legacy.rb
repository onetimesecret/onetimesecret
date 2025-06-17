# lib/onetime/legacy.rb

module Onetime
  class << self

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
