# apps/api/colonel/logic/colonel/export_usage.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class ExportUsage < ColonelAPI::Logic::Base
        using Familia::Refinements::TimeLiterals

        attr_reader :start_date, :end_date, :usage_data, :secrets_by_day, :users_by_day

        def process_params
          # Parse date parameters (Unix timestamps)
          @start_date = params['start_date'] ? params['start_date'].to_i : (Familia.now.to_i - 30.days)
          @end_date   = params['end_date'] ? params['end_date'].to_i : Familia.now.to_i

          # Validate date range
          if start_date > end_date
            raise_form_error('Start date must be before end date', field: :start_date)
          end

          if end_date - start_date > 365.days
            raise_form_error('Date range cannot exceed 365 days', field: :end_date)
          end
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get all secrets in date range using non-blocking SCAN
          secrets_in_range = scan_secrets_in_date_range

          # Get all customers and filter by date range
          all_customers_objids = Onetime::Customer.instances.to_a
          all_customers        = Onetime::Customer.load_multi(all_customers_objids).compact
          customers_in_range   = all_customers.select do |cust|
            cust.created && cust.created >= start_date && cust.created <= end_date && !cust.anonymous?
          end

          # Group secrets by day
          @secrets_by_day = secrets_in_range.group_by do |secret|
            Time.at(secret.created).utc.strftime('%Y-%m-%d')
          end.transform_values(&:count)

          # Group users by day
          @users_by_day = customers_in_range.group_by do |cust|
            Time.at(cust.created).utc.strftime('%Y-%m-%d')
          end.transform_values(&:count)

          # Calculate statistics
          @usage_data = {
            total_secrets: secrets_in_range.size,
            total_new_users: customers_in_range.size,
            secrets_by_state: secrets_in_range.group_by(&:state).transform_values(&:count),
            avg_secrets_per_day: secrets_in_range.size.to_f / ((end_date - start_date) / 86_400.0),
            avg_users_per_day: customers_in_range.size.to_f / ((end_date - start_date) / 86_400.0),
          }

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              date_range: {
                start_date: start_date,
                start_date_human: Time.at(start_date).utc.strftime('%Y-%m-%d'),
                end_date: end_date,
                end_date_human: Time.at(end_date).utc.strftime('%Y-%m-%d'),
                days: ((end_date - start_date) / 86_400.0).ceil,
              },
              usage_data: usage_data,
              secrets_by_day: secrets_by_day,
              users_by_day: users_by_day,
            },
          }
        end

        private

        # Scan secrets in date range using non-blocking Redis SCAN
        # Replaces blocking KEYS operation
        def scan_secrets_in_date_range
          secrets  = []
          cursor   = '0'
          dbclient = Onetime::Secret.new.dbclient
          pattern  = 'secret:*:object'

          loop do
            cursor, keys = dbclient.scan(cursor, match: pattern, count: 100)

            keys.each do |key|
              objid  = key.split(':')[1]
              secret = Onetime::Secret.load(objid)
              next unless secret&.exists?
              next unless secret.created && secret.created >= start_date && secret.created <= end_date

              secrets << secret
            end

            break if secrets.size >= 10_000
            break if cursor == '0'
          end

          secrets
        end
      end
    end
  end
end
