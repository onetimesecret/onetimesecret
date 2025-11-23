# apps/api/account/logic/colonel/list_users.rb
#
# frozen_string_literal: true

require_relative '../base'

module AccountAPI
  module Logic
    module Colonel
      class ListUsers < AccountAPI::Logic::Base
        attr_reader :users, :total_count, :page, :per_page, :total_pages, :role_filter

        def process_params
          @page = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
          @per_page = 100 if @per_page > 100 # Max 100 per page
          @page = 1 if @page < 1
          @role_filter = params['role'] # Optional: filter by role
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get all customers
          all_customers = Onetime::Customer.instances.to_a

          # Filter by role if specified
          if role_filter && !role_filter.empty?
            all_customers = all_customers.select { |cust| cust.role == role_filter }
          end

          @total_count = all_customers.size
          @total_pages = (@total_count.to_f / @per_page).ceil

          # Sort by created timestamp (most recent first)
          all_customers.sort_by! { |cust| -(cust.created || 0) }

          # Paginate
          start_idx = (@page - 1) * @per_page
          end_idx = start_idx + @per_page - 1
          paginated_customers = all_customers[start_idx..end_idx] || []

          # Format user data
          @users = paginated_customers.map do |cust|
            next if cust.anonymous?

            # Count secrets owned by this user
            user_secrets_count = Onetime::Secret.new.dbclient.keys("secret*:object").select do |key|
              objid = key.split(':')[1]
              secret = Onetime::Secret.load(objid)
              secret&.owner_id == cust.objid
            end.count

            {
              user_id: cust.objid,
              extid: cust.extid,
              email: cust.obscure_email,
              role: cust.role,
              verified: cust.verified?,
              created: cust.created,
              created_human: natural_time(cust.created),
              last_login: cust.last_login,
              last_login_human: cust.last_login ? natural_time(cust.last_login) : 'Never',
              planid: cust.planid,
              secrets_count: user_secrets_count,
              secrets_created: cust.respond_to?(:secrets_created) ? cust.secrets_created : 0,
              secrets_shared: cust.respond_to?(:secrets_shared) ? cust.secrets_shared : 0,
            }
          end.compact

          success_data
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
