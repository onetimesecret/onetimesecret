# lib/onetime/application/error_resolver.rb
#
# frozen_string_literal: true

require 'i18n'

module Onetime
  module Application
    # Resolves the i18n shape of OT errors at the HTTP edge.
    #
    # Errors raised from logic classes can carry an error_key (full dotted
    # i18n key) and args (interpolation values). This module resolves them
    # into a localized message using the request locale, mutating the error
    # in place. Errors that don't carry an error_key are left untouched so
    # legacy positional-string errors keep working.
    #
    # Lives in its own module rather than inside OttoHooks so it's
    # unit-testable in isolation, and so non-Otto edges (e.g. Rack rescuers
    # in legacy controllers) can call it too.
    module ErrorResolver
      module_function

      # Mutate `error` in place: if it carries an i18n error_key, replace
      # its message with the localized rendering for `req`'s locale.
      #
      # Resolution policy: error_key always wins when present. Callers that
      # also pass a legacy message (e.g. verify_one_of_roles! during the
      # transition) get their message overwritten with the localized version
      # — the legacy English string is the fallback when I18n.t doesn't find
      # the key. Errors with no error_key are returned unchanged, so legacy
      # positional-string errors keep working without per-class flags.
      #
      # @param error [Exception] Any error; resolver inspects for error_key
      # @param req [Rack::Request, nil] Used to read otto.locale; may be nil
      # @return [Exception] The same error (for chaining), with message set
      def resolve!(error, req)
        return error unless error.respond_to?(:error_key) && error.error_key
        return error unless error.respond_to?(:message=)

        locale   = req&.env&.[]('otto.locale') || I18n.default_locale
        args     = error.respond_to?(:args) ? (error.args || {}) : {}
        fallback = error.message.to_s.empty? ? error.error_key.to_s : error.message

        error.message = I18n.t(error.error_key, locale: locale,
                                                  default: fallback,
                                                  **args)
        error
      rescue StandardError => ex
        # Fallback: never let i18n failure cause a 500 — leave the error_key
        # itself as the message so the client still gets something useful.
        OT.le "[ErrorResolver] Failed to resolve #{error.error_key} (#{ex.class}): #{ex.message}"
        if error.respond_to?(:message=) && (error.message.nil? || error.message.to_s.empty?)
          error.message = error.error_key.to_s
        end
        error
      end
    end
  end
end
