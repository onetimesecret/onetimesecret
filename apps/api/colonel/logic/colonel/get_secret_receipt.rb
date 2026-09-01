# apps/api/colonel/logic/colonel/get_secret_receipt.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Read one secret's receipt and owner (GET /api/colonel/secrets/:secret_id/receipt).
      #
      # ## Audited as an OBSERVATION (#4335)
      #
      # Mutates nothing, so it writes nothing to the OPERATOR trail. It is on
      # the curated list for the access trail because of what it discloses: the
      # response carries the OWNER'S FULL EMAIL ADDRESS alongside the secret's
      # state and receipt. Looking up who owns a given secret is precisely the
      # kind of operator action that needs to be attributable afterwards.
      #
      # `detail` names the shortid and whether an owner was resolved — never
      # the owner's address, and never any secret material. The response body
      # is a colonel-only surface; the audit trail is a longer-lived record and
      # is held to the tighter standard.
      class GetSecretReceipt < ColonelAPI::Logic::Base
        AUDIT_VERB = 'secret.receipt_view'

        attr_reader :secret_id, :secret, :receipt, :owner

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

          # Load owner
          if secret.owner_id && secret.owner_id != 'anon'
            @owner = Onetime::Customer.load(secret.owner_id)
          end
        end

        def process
          record_access_event

          success_data
        end

        # PUBLIC ids only: the secret's shortid, and booleans for what the
        # read-out exposed. No email, no objid, no ciphertext facts.
        def record_access_event
          Onetime::ColonelAuditEvent.record_access(
            actor: cust&.extid,
            verb: AUDIT_VERB,
            target: secret.shortid,
            result: :success,
            detail: {
              state: secret.state.to_s,
              owner_extid: owner&.extid,
              receipt_shortid: receipt&.shortid,
            },
          )
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
              receipt_id: secret.receipt_identifier,
              has_ciphertext: !secret.ciphertext.to_s.empty?,
              ciphertext_length: secret.ciphertext.to_s.length,
            },
            details: {
              metadata: if receipt # maintain public API
  {
    receipt_id: receipt.objid,
    shortid: receipt.shortid,
    state: receipt.state,
    secret_ttl: receipt.secret_ttl,
    recipients: receipt.recipients,
    has_passphrase: receipt.has_passphrase?,
    share_domain: receipt.share_domain,
    created: receipt.created,
    secret_expired: receipt.secret_expired?,
  }
end,
              owner: if owner
  {
    user_id: owner.objid,
    # FULL address (colonel-only, scope=internal); obscured client-side and
    # revealed on interaction via RevealEmail.vue.
    email: owner.email,
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
