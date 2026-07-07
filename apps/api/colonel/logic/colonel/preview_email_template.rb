# apps/api/colonel/logic/colonel/preview_email_template.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/preview_template'

module ColonelAPI
  module Logic
    module Colonel
      # Render an email template for visual inspection (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Email::PreviewTemplate} — the
      # single implementation shared with the `bin/ots email preview` CLI (ticket
      # #44). The op owns sample-data resolution + rendering; this class keeps the
      # HTTP concerns (param extraction, unknown-template + missing-sample → form
      # errors).
      #
      # READ-ONLY: rendering has NO side effects (it never dispatches an email), so
      # it records NO AdminAuditEvent (CONTRACT 4). Over HTTP the preview always
      # uses the template's SAMPLE data — no operator-supplied variables — so a
      # preview can never carry live customer data.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class PreviewEmailTemplate < ColonelAPI::Logic::Base
        attr_reader :template, :locale, :format, :result

        def process_params
          @template = params['template'].to_s
          @locale   = params['locale'].to_s.empty? ? 'en' : params['locale'].to_s
          @format   = params['format'].to_s == 'html' ? 'html' : 'text'
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Template is required', field: :template) if template.empty?

          unless Onetime::Operations::Email::AVAILABLE_TEMPLATES.include?(template.to_sym)
            raise_not_found("Unknown template: #{template}")
          end
        end

        def process
          # data: nil → the op loads the template's sample fixture. No custom data
          # is accepted over HTTP (parity-safe + avoids injecting live data).
          @result = Onetime::Operations::Email::PreviewTemplate.new(
            template: template,
            data: nil,
            locale: locale,
            format: format,
          ).call

          success_data
        rescue Onetime::Operations::Email::PreviewTemplate::MissingSampleError => ex
          raise_form_error(ex.message, field: :template)
        rescue ArgumentError => ex
          raise_form_error(ex.message, field: :template)
        end

        def success_data
          {
            record: {
              template: result.template,
              locale: result.locale,
              format: result.format,
            },
            details: {
              body: result.body,
            },
          }
        end
      end
    end
  end
end
