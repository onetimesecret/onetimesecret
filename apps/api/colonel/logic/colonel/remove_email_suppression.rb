# apps/api/colonel/logic/colonel/remove_email_suppression.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/remove_suppression'

module ColonelAPI
  module Logic
    module Colonel
      # Remove an address from the email suppression list (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Email::RemoveSuppression} — the
      # single, audited implementation of the suppression-remove verb. This
      # class keeps only the HTTP concerns (param validation + the not-found
      # 404); the op owns the model mutation and the AdminAuditEvent
      # (CONTRACT 4). The UnbanIP adapter pattern, applied to addresses.
      #
      # Removing a suppression re-enables sending to an address that bounced
      # or complained, so the UI gates it behind an AdminConfirmDialog.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class RemoveEmailSuppression < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailSuppressionRemove' }.freeze

        attr_reader :address, :removed

        def process_params
          # The path param arrives URL-decoded (Otto unescapes PATH_INFO), so a
          # client-side encodeURIComponent'd address round-trips intact.
          @address = Onetime::EmailSuppression.normalize(params['address'])
          raise_form_error('Address is required', field: :address) if address.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          unless Onetime::EmailSuppression.suppressed?(address)
            raise_not_found('Address is not suppressed')
          end
        end

        def process
          # Delegate the model mutation + audit to the single op implementation.
          # actor is the acting colonel's PUBLIC id (never an objid).
          result   = Onetime::Operations::Email::RemoveSuppression.new(
            address: address,
            actor: cust.extid,
          ).call
          @removed = result.status == :removed

          success_data
        end

        def success_data
          {
            record: {
              address: address,
              removed: removed,
            },
            details: {
              message: 'Suppression removed successfully',
            },
          }
        end
      end
    end
  end
end
