# apps/api/account/logic/colonel/get_user_details.rb
#
# frozen_string_literal: true

require_relative '../base'

module AccountAPI
  module Logic
    module Colonel
      class GetUserDetails < AccountAPI::Logic::Base
        attr_reader :user_id, :user, :user_secrets, :user_metadata, :organizations

        def process_params
          @user_id = params['user_id']
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @user = Onetime::Customer.load(user_id)
          raise_not_found('User not found') unless user&.exists?
        end

        def process
          # Get all secrets owned by this user
          all_secret_keys = Onetime::Secret.new.dbclient.keys('secret*:object')
          @user_secrets = all_secret_keys.select do |key|
            objid = key.split(':')[1]
            secret = Onetime::Secret.load(objid)
            secret&.owner_id == user.objid
          end.map do |key|
            objid = key.split(':')[1]
            secret = Onetime::Secret.load(objid)
            {
              secret_id: secret.objid,
              shortid: secret.shortid,
              state: secret.state,
              created: secret.created,
              created_human: natural_time(secret.created),
              expiration: secret.expiration,
              expiration_human: natural_time(secret.expiration),
            }
          end

          # Get all metadata owned by this user
          all_metadata_keys = Onetime::Metadata.new.dbclient.keys('metadata*:object')
          @user_metadata = all_metadata_keys.select do |key|
            objid = key.split(':')[1]
            metadata = Onetime::Metadata.load(objid)
            metadata&.owner_id == user.objid
          end.map do |key|
            objid = key.split(':')[1]
            metadata = Onetime::Metadata.load(objid)
            {
              metadata_id: metadata.objid,
              shortid: metadata.shortid,
              state: metadata.state,
              created: metadata.created,
              created_human: natural_time(metadata.created),
            }
          end

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

        def success_data
          {
            record: {
              user_id: user.objid,
              extid: user.extid,
              email: user.obscure_email,
              role: user.role,
              verified: user.verified?,
              created: user.created,
              created_human: natural_time(user.created),
              updated: user.updated,
              updated_human: natural_time(user.updated),
              last_login: user.last_login,
              last_login_human: user.last_login ? natural_time(user.last_login) : 'Never',
              planid: user.planid,
              locale: user.locale,
            },
            details: {
              secrets: {
                count: user_secrets.size,
                items: user_secrets,
              },
              metadata: {
                count: user_metadata.size,
                items: user_metadata,
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
