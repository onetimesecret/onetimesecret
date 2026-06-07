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
    # ## Message precedence
    #
    # When both error_key and a pre-set message are present (the "hybrid"
    # shape used by verify_authenticated! and the verify_one_of_roles!
    # callers in apps/api/organizations/logic/base.rb), the resolved I18n
    # string always wins — the pre-set message is treated as the English
    # fallback that I18n.t falls back to when the key is missing from the
    # active locale, not as the source of truth.
    #
    # Priority for the final error.message:
    #   1. I18n.t(error_key, locale: req_locale, **args) — if the key exists
    #      in the active locale's bundle (or any fallback locale)
    #   2. The pre-set legacy message (passed as `default:` to I18n.t) — if
    #      the key is missing everywhere
    #   3. error_key.to_s — if (2) is also empty
    #
    # This means specs that match on the English message keep working as long
    # as the en.json bundle has the key with the same English text. Specs
    # that boot without I18n won't see resolution at all (resolve! is a
    # no-op at the edge, not in logic), so e.error_key is the safe assertion.
    #
    # Lives in its own module rather than inside OttoHooks so it's
    # unit-testable in isolation, and so non-Otto edges (e.g. Rack rescuers
    # in legacy controllers) can call it too.
    module ErrorResolver
      module_function

      # Mutate `error` in place: if it carries an i18n error_key, replace
      # its message with the localized rendering for `req`'s locale.
      #
      # See module-level precedence rule: error_key always wins when present;
      # any pre-set message becomes the I18n.t fallback (default:), not the
      # source of truth. Errors with no error_key are returned unchanged.
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
