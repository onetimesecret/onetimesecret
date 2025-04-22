# apps/api/v2/controllers/meta.rb

require 'json'
require 'base64'

require_relative 'base'
require_relative 'class_methods'
require_relative 'settings'

module V2
  module Controllers
    class Meta
      include ControllerBase
      include ControllerSettings

      def status
        publically do
          json status: :nominal, locale: locale
        end
      end

      def authcheck
        authorized do
          response = {
            record: cust.safe_dump,
            details: { authenticated: sess.authenticated? },
          }
          json response
        end
      end

      def version
        publically do
          json version: OT::VERSION.to_a, locale: locale
        end
      end

      def receive_feedback
        process_action(
          V2::Logic::ReceiveFeedback,
          "Feedback received. Send as much as you like.",
          "Sorry we were not able to receive your feedback (it's us, not you).",
          allow_anonymous: true,
        )
      end

      def receive_exception
        process_action(
          V2::Logic::ReceiveException,
          "Exception received. No offense taken.",
          "Sorry we were not able to receive your exception (it's us, not you).",
          allow_anonymous: true,
        )
      end

      def get_supported_locales
        publically do
          supported_locales = OT.supported_locales.map(&:to_s)
          default_locale = OT.default_locale
          json locales: supported_locales, default_locale: default_locale, locale: locale
        end
      end

      def get_validate_shrimp
        publically do
          carefully do
            # NOTE: Unlike `check_shrimp!`, this method only considers
            # the Official Shrimp HTTP Header. The endpoint it supports
            # is used by the Vue app as a Just-In-Time check to try to
            # avoid scenarios where we have an outdated shrimp and an
            # important request fails inexplicably for the user.

            # Log all headers for debugging Sentry issue
            OT.ld "[Debug-Sentry] Request headers: #{req.env.select { |k, v| k.start_with?('HTTP_') }.inspect}"

            shrimp = req.env['HTTP_O_SHRIMP'].to_s
            OT.le 'Missing O-Shrimp header' if shrimp.empty?

            begin
              # Attempt to validate the shrimp
              is_valid = validate_shrimp(shrimp, replace=false)
            rescue OT::BadShrimp => e
              # If a BadShrimp exception is raised, log it and set is_valid to false
              OT.ld "BadShrimp exception: #{e.message}"
              is_valid = false
            end

            sess.replace_shrimp! unless is_valid

            ret = {
              isValid: is_valid,
              shrimp: sess.shrimp,
            }
            json ret
          end
        end
      end

      extend V2::Controllers::ClassMethods
    end
  end
end
