# apps/api/colonel/logic/colonel/get_user_details.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class GetUserDetails < ColonelAPI::Logic::Base
        attr_reader :user_id, :user, :user_secrets, :user_receipts, :organizations

        def process_params
          @user_id = sanitize_identifier(params['user_id'])
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve by PUBLIC id (extid) first — the users list exposes only
          # extid, so every admin surface routes/fetches by it — then email,
          # then objid. Mirrors Auth::Operations::Customers::Show#resolve
          # (show.rb): a plain Customer.load only resolves the internal objid
          # (identifier_field :objid), so an extid would 404.
          @user = Onetime::Customer.load_by_extid_or_email(user_id) ||
                  Onetime::Customer.load(user_id)
          raise_not_found('User not found') unless user&.exists?
        end

        def process
          # Get all secrets owned by this user using non-blocking SCAN
          @user_secrets = scan_user_secrets

          # Get all receipts owned by this user using non-blocking SCAN
          @user_receipts = scan_user_receipts

          # Get user's organizations (if they participate in any)
          @organizations = []
          if user.respond_to?(:organizations)
            user.organizations.each do |org_id|
              org = Onetime::Organization.load(org_id)
              next unless org&.exists?

              @organizations << {
                organization_id: org.objid,
                extid: org.extid,
                display_name: org.display_name,
                is_default: org.is_default,
              }
            end
          end

          success_data
        end

        private

        # Scan secrets owned by user using non-blocking Redis SCAN.
        # O(all secrets) but filters by owner_id. The user.receipts sorted
        # set would be more efficient but isn't populated by spawn_pair yet.
        #
        # SCOPE (#60): this detail view intentionally keeps its own bounded
        # cursor SCAN and does NOT source `details.secrets.count` from the
        # maintained `secrets_active` counter. #60's "count correct beyond 10k"
        # criterion applies to the colonel USERS LIST column (ListUsers), which
        # shows only a count. Here we render the actual secret ITEMS, so the
        # count must equal the items shown (`details.secrets.count == items.size`).
        # Sourcing it from `secrets_active` would surface a visible count/items
        # mismatch because that counter drifts UP between nightly reconciliations
        # (no TTL-expiry decrement — see Customer::Features::CounterFields). This
        # is a bounded, non-blocking cursor SCAN (COUNT=100, 10k cap), so it is
        # CONTRACT-8 compliant — not the blocking KEYS/SMEMBERS the #2211 incident
        # forbids. list_secrets.rb / export_usage.rb keep similar bounded SCANs
        # for the same reason (separate features). Removing the full-keyspace scan
        # via a per-owner secret index is a separate follow-up.
        def scan_user_secrets
          secrets  = []
          cursor   = '0'
          dbclient = Onetime::Secret.dbclient
          pattern  = 'secret:*:object'

          loop do
            cursor, keys = dbclient.scan(cursor, match: pattern, count: 100)

            keys.each do |key|
              objid  = key.split(':')[1]
              secret = Onetime::Secret.load(objid)
              next unless secret&.exists?
              next unless secret.owner_id == user.objid

              secrets << {
                secret_id: secret.objid,
                shortid: secret.shortid,
                state: secret.state,
                created: secret.created,
                expiration: secret.expiration,
              }
            end

            break if secrets.size >= 10_000
            break if cursor == '0'
          end

          secrets
        end

        # Scan receipts owned by user using non-blocking Redis SCAN.
        def scan_user_receipts
          receipt_list = []
          cursor       = '0'
          dbclient     = Onetime::Receipt.dbclient
          pattern      = 'receipt:*:object'

          loop do
            cursor, keys = dbclient.scan(cursor, match: pattern, count: 100)

            keys.each do |key|
              objid   = key.split(':')[1]
              receipt = Onetime::Receipt.load(objid)
              next unless receipt&.exists?
              next unless receipt.owner_id == user.objid

              receipt_list << {
                receipt_id: receipt.objid,
                shortid: receipt.shortid,
                state: receipt.state,
                created: receipt.created,
              }
            end

            break if receipt_list.size >= 10_000
            break if cursor == '0'
          end

          receipt_list
        end

        def success_data
          {
            record: {
              extid: user.extid,
              email: user.obscure_email,
              role: user.role,
              verified: user.verified?,
              created: user.created,
              updated: user.updated,
              last_login: user.last_login,
              planid: user.planid,
              locale: user.locale,
            },
            details: {
              secrets: {
                count: user_secrets.size,
                items: user_secrets,
              },
              receipts: {
                count: user_receipts.size,
                items: user_receipts,
              },
              organizations: organizations,
              # Counters are Familia::Counter objects (familia 2.8); coerce
              # to Integer before serialization so JSON's Enumerable path
              # doesn't try to .each over an opaque Counter.
              stats: {
                secrets_created: user.respond_to?(:secrets_created) ? user.secrets_created.to_i : 0,
                secrets_shared: user.respond_to?(:secrets_shared) ? user.secrets_shared.to_i : 0,
                emails_sent: user.respond_to?(:emails_sent) ? user.emails_sent.to_i : 0,
              },
            },
          }
        end
      end
    end
  end
end
