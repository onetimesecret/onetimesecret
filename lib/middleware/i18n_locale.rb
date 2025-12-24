# lib/middleware/i18n_locale.rb
#
# frozen_string_literal: true

module Middleware
  # I18nLocale middleware
  #
  # Sets the I18n.locale for the duration of the request based on the
  # locale detected by Otto::Locale::Middleware (stored in otto.locale).
  #
  # This middleware provides thread-safe locale scoping using I18n.with_locale,
  # ensuring each request operates in its own locale context without affecting
  # other concurrent requests.
  #
  # Middleware order:
  # 1. Otto::Locale::Middleware sets env['otto.locale']
  # 2. This middleware reads env['otto.locale'] and wraps the request
  #
  # Usage:
  #   use Middleware::I18nLocale
  #
  class I18nLocale
    def initialize(app)
      @app = app
    end

    # Process the request with scoped I18n.locale
    #
    # @param env [Hash] Rack environment
    # @return [Array] Rack response tuple
    #
    def call(env)
      # Get locale from Otto middleware or fall back to default
      locale = env['otto.locale'] || I18n.default_locale

      # Ensure locale is a symbol for I18n
      locale_sym = locale.to_sym

      # Set locale for this request thread only
      I18n.with_locale(locale_sym) do
        @app.call(env)
      end
    end
  end
end
