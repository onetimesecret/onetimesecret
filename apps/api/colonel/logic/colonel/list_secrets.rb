# apps/api/colonel/logic/colonel/list_secrets.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class ListSecrets < ColonelAPI::Logic::Base
        attr_reader :secrets, :total_count, :page, :per_page, :total_pages

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
          @per_page = 100 if @per_page > 100 # Max 100 per page
          @page     = 1 if @page < 1
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get all secret keys from Redis
          secret_keys  = Onetime::Secret.new.dbclient.keys('secret*:object')
          @total_count = secret_keys.size
          @total_pages = (@total_count.to_f / @per_page).ceil

          # Paginate
          start_idx      = (@page - 1) * @per_page
          end_idx        = start_idx + @per_page - 1
          paginated_keys = secret_keys[start_idx..end_idx] || []

          # Load secret data
          @secrets = paginated_keys.map do |key|
            # Extract objid from key (e.g., "secret:abc123:object" -> "abc123")
            objid  = key.split(':')[1]
            secret = Onetime::Secret.load(objid)
            next unless secret&.exists?

            {
              secret_id: secret.objid,
              shortid: secret.shortid,
              owner_id: secret.owner_id,
              state: secret.state,
              created: secret.created,
              expiration: secret.expiration,
              lifespan: secret.lifespan,
              metadata_id: secret.metadata_identifier,
              age: secret.age,
              has_ciphertext: !secret.ciphertext.to_s.empty?,
            }
          end.compact

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              secrets: secrets,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
              },
            },
          }
        end
      end
    end
  end
end
