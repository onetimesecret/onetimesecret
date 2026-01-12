# apps/api/colonel/logic/colonel/delete_secret.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class DeleteSecret < ColonelAPI::Logic::Base
        attr_reader :secret_id, :secret, :receipt, :deleted_secret, :deleted_receipt

        def process_params
          @secret_id = sanitize_identifier(params['secret_id'])
          raise_form_error('Secret ID is required', field: :secret_id) if secret_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @secret = Onetime::Secret.load(secret_id)
          raise_not_found('Secret not found') unless secret&.exists?

          # Load associated receipt
          if secret.receipt_identifier
            @receipt = Onetime::Receipt.load(secret.receipt_identifier)
          end
        end

        def process
          # Delete receipt first (if exists)
          if receipt&.exists?
            @deleted_receipt = {
              receipt_id: receipt.objid,
              shortid: receipt.shortid,
            }
            receipt.destroy!
          end

          # Delete secret
          @deleted_secret = {
            secret_id: secret.objid,
            shortid: secret.shortid,
            state: secret.state,
            owner_id: secret.owner_id,
          }
          secret.destroy!

          success_data
        end

        def success_data
          {
            record: {
              deleted: true,
              secret: deleted_secret,
              metadata: deleted_receipt, # maintain public API
            },
            details: {
              message: 'Secret and associated receipt deleted successfully',
            },
          }
        end
      end
    end
  end
end
