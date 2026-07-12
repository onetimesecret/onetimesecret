# apps/api/colonel/logic/colonel/add_email_suppression.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/add_suppression'

module ColonelAPI
  module Logic
    module Colonel
      # Manually add an address to the email suppression list (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Email::AddSuppression} — the
      # single, audited implementation of the manual-suppress verb (the mirror
      # of {RemoveEmailSuppression}). This class keeps only the HTTP concerns
      # (address validation); the op owns the model mutation and the
      # AdminAuditEvent (CONTRACT 4).
      #
      # The request carries ONLY `address`. `reason` is hardcoded 'manual' and
      # `source` is hardcoded 'colonel' SERVER-SIDE — a client-supplied
      # reason='bounce' would mislabel a manual entry, and source is a displayed
      # list column.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class AddEmailSuppression < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailSuppressionAdd' }.freeze

        attr_reader :address, :created

        def process_params
          @address = Onetime::EmailSuppression.normalize(params['address'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Address is required', field: :address) if address.empty?
        end

        def process
          # Delegate the model mutation + audit to the single op implementation.
          # actor is the acting colonel's PUBLIC id (never an objid). reason and
          # source are fixed here — the client cannot influence them.
          result   = Onetime::Operations::Email::AddSuppression.new(
            address: address,
            actor: cust.extid,
            reason: 'manual',
            source: 'colonel',
          ).call
          @created = result.status == :created

          success_data
        end

        def success_data
          {
            record: {
              address: address,
              created: created,
            },
            details: {
              message: 'Address suppressed.',
            },
          }
        end
      end
    end
  end
end
