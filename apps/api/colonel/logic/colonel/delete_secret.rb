# apps/api/colonel/logic/colonel/delete_secret.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class DeleteSecret < ColonelAPI::Logic::Base
        attr_reader :secret_id, :secret, :metadata, :deleted_secret, :deleted_metadata

        def process_params
          @secret_id = params['secret_id']
          raise_form_error('Secret ID is required', field: :secret_id) if secret_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @secret = Onetime::Secret.load(secret_id)
          raise_not_found('Secret not found') unless secret&.exists?

          # Load associated metadata
          if secret.metadata_identifier
            @metadata = Onetime::Metadata.load(secret.metadata_identifier)
          end
        end

        def process
          # Delete metadata first (if exists)
          if metadata&.exists?
            @deleted_metadata = {
              metadata_id: metadata.objid,
              shortid: metadata.shortid,
            }
            metadata.destroy!
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
              metadata: deleted_metadata,
            },
            details: {
              message: 'Secret and associated metadata deleted successfully',
            },
          }
        end
      end
    end
  end
end
