# apps/api/colonel/logic/colonel/get_secret_metadata.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class GetSecretMetadata < ColonelAPI::Logic::Base
        attr_reader :secret_id, :secret, :metadata, :owner

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

          # Load owner
          if secret.owner_id && secret.owner_id != 'anon'
            @owner = Onetime::Customer.load(secret.owner_id)
          end
        end

        def process
          success_data
        end

        def success_data
          {
            record: {
              secret_id: secret.objid,
              shortid: secret.shortid,
              state: secret.state,
              lifespan: secret.lifespan,
              created: secret.created,
              updated: secret.updated,
              expiration: secret.expiration,
              age: secret.age,
              owner_id: secret.owner_id,
              metadata_id: secret.metadata_identifier,
              has_ciphertext: !secret.ciphertext.to_s.empty?,
              ciphertext_length: secret.ciphertext.to_s.length,
            },
            details: {
              metadata: if metadata
  {
    metadata_id: metadata.objid,
    shortid: metadata.shortid,
    state: metadata.state,
    secret_ttl: metadata.secret_ttl,
    recipients: metadata.recipients,
    has_passphrase: metadata.has_passphrase?,
    share_domain: metadata.share_domain,
    created: metadata.created,
    secret_expired: metadata.secret_expired?,
  }
end,
              owner: if owner
  {
    user_id: owner.objid,
    email: owner.obscure_email,
    role: owner.role,
    verified: owner.verified?,
  }
end,
            },
          }
        end
      end
    end
  end
end
