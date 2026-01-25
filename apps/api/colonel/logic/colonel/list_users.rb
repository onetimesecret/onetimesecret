# apps/api/colonel/logic/colonel/list_users.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class ListUsers < ColonelAPI::Logic::Base
        attr_reader :users, :total_count, :page, :per_page, :total_pages, :role_filter

        def process_params
          @page        = (params['page'] || 1).to_i
          @per_page    = (params['per_page'] || 50).to_i
          @per_page    = 100 if @per_page > 100 # Max 100 per page
          @page        = 1 if @page < 1
          @role_filter = sanitize_plain_text(params['role']) # Optional: filter by role
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get all customers
          all_customers_objids = Onetime::Customer.instances.to_a
          all_customers        = Onetime::Customer.load_multi(all_customers_objids).compact

          # Filter by role if specified
          if role_filter && !role_filter.empty?
            all_customers = all_customers.select { |cust| cust.role == role_filter }
          end

          @total_count = all_customers.size # or Onetime::Customer.count to count via zset index
          @total_pages = (@total_count.to_f / @per_page).ceil

          # Sort by created timestamp (most recent first)
          all_customers.sort_by! { |cust| -(cust.created || 0) }

          # Paginate
          start_idx           = (@page - 1) * @per_page
          end_idx             = start_idx + @per_page - 1
          paginated_customers = all_customers[start_idx..end_idx] || []

          # Build owner_id -> secret count index using non-blocking SCAN
          # This is done once per request instead of per-user to avoid O(N*M)
          secrets_count_by_owner = build_secrets_count_by_owner

          # Format user data
          @users = paginated_customers.map do |cust|
            next if cust.anonymous?

            {
              user_id: cust.objid,
              extid: cust.extid,
              email: cust.obscure_email,
              role: cust.role,
              verified: cust.verified?,
              created: cust.created,
              last_login: cust.last_login,
              planid: cust.planid,
              secrets_count: secrets_count_by_owner[cust.objid] || 0,
              secrets_created: cust.respond_to?(:secrets_created) ? cust.secrets_created : 0,
              secrets_shared: cust.respond_to?(:secrets_shared) ? cust.secrets_shared : 0,
            }
          end.compact

          success_data
        end

        private

        # Build a hash of owner_id -> secret count using non-blocking Redis SCAN
        # This replaces the O(N*M) pattern of calling KEYS inside a loop
        def build_secrets_count_by_owner
          counts   = Hash.new(0)
          cursor   = '0'
          dbclient = Onetime::Secret.new.dbclient
          pattern  = 'secret:*:object'

          loop do
            cursor, keys = dbclient.scan(cursor, match: pattern, count: 100)

            keys.each do |key|
              objid  = key.split(':')[1]
              secret = Onetime::Secret.load(objid)
              next unless secret&.exists?

              counts[secret.owner_id] += 1 if secret.owner_id
            end

            break if counts.size >= 10_000
            break if cursor == '0'
          end

          counts
        end

        def success_data
          {
            record: {},
            details: {
              users: users,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
                role_filter: role_filter,
              },
            },
          }
        end
      end
    end
  end
end
