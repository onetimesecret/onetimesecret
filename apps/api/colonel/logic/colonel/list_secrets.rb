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
          # Get paginated secrets using non-blocking SCAN
          result       = scan_secrets_paginated
          @secrets     = result[:secrets]
          @total_count = result[:total_count]
          @total_pages = (@total_count.to_f / @per_page).ceil

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

        private

        # Scan secrets using non-blocking Redis SCAN with in-memory pagination
        # Replaces blocking KEYS operation
        #
        # Note: For very large datasets, consider implementing cursor-based pagination
        # where the cursor is passed to the client for subsequent requests
        def scan_secrets_paginated
          all_secrets = []
          cursor      = '0'
          dbclient    = Onetime::Secret.new.dbclient
          pattern     = 'secret:*:object'

          loop do
            cursor, keys = dbclient.scan(cursor, match: pattern, count: 100)

            keys.each do |key|
              objid  = key.split(':')[1]
              secret = Onetime::Secret.load(objid)
              next unless secret&.exists?

              all_secrets << {
                secret_id: secret.objid,
                shortid: secret.shortid,
                owner_id: secret.owner_id,
                state: secret.state,
                created: secret.created,
                expiration: secret.expiration,
                lifespan: secret.lifespan,
                receipt_id: secret.receipt_identifier,
                age: secret.age,
                has_ciphertext: !secret.ciphertext.to_s.empty?,
              }
            end

            break if all_secrets.size >= 10_000
            break if cursor == '0'
          end

          # Sort by created timestamp (most recent first)
          all_secrets.sort_by! { |s| -(s[:created] || 0) }

          # Apply pagination
          start_idx = (page - 1) * per_page
          end_idx   = start_idx + per_page - 1
          paginated = all_secrets[start_idx..end_idx] || []

          { secrets: paginated, total_count: all_secrets.size }
        end
      end
    end
  end
end
