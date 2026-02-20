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

          @user = Onetime::Customer.load(user_id)
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

        # Scan secrets owned by user using non-blocking Redis SCAN
        # Replaces blocking KEYS operation
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

        # Scan receipts owned by user using non-blocking Redis SCAN
        # Replaces blocking KEYS operation
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
              stats: {
                secrets_created: user.respond_to?(:secrets_created) ? user.secrets_created : 0,
                secrets_shared: user.respond_to?(:secrets_shared) ? user.secrets_shared : 0,
                emails_sent: user.respond_to?(:emails_sent) ? user.emails_sent : 0,
              },
            },
          }
        end
      end
    end
  end
end
