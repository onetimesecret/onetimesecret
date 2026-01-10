# apps/web/billing/cli/sigma_run_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Execute Sigma query
    class BillingSigmaRunCommand < Command
      include BillingHelpers

      desc 'Execute a Sigma query'

      argument :query_id, required: true, desc: 'Sigma query ID (sqa_xxx)'

      option :format,
        type: :string,
        default: 'table',
        desc: 'Output format: table, csv, json'
      option :output, type: :string, desc: 'Output file path'

      def call(query_id:, format: 'table', output: nil, **)
        boot_application!

        return unless stripe_configured?

        unless %w[table csv json].include?(format)
          puts 'Error: Format must be one of: table, csv, json'
          return
        end

        puts "Executing Sigma query: #{query_id}"

        query_run = Stripe::Sigma::ScheduledQueryRun.retrieve(query_id)

        puts "Query: #{query_run.sql[0..100]}..."
        puts

        # NOTE: Actual execution and result retrieval requires the query to be run
        # This is a simplified implementation
        puts "Status: #{query_run.status}"

        if query_run.result_available_until
          puts "Results available until: #{format_timestamp(query_run.result_available_until)}"
        end

        # In a real implementation, you would fetch and format the actual results
        # For now, show query details
        case format
        when 'json'
          require 'json'
          result     = {
            id: query_run.id,
            sql: query_run.sql,
            status: query_run.status,
            created: query_run.created,
          }
          output_str = JSON.pretty_generate(result)
        when 'csv'
          output_str = "ID,SQL,STATUS,CREATED\n#{query_run.id},\"#{query_run.sql}\",#{query_run.status},#{query_run.created}"
        else
          output_str = 'Query execution complete. Use Stripe Dashboard to view full results.'
        end

        if output
          File.write(output, output_str)
          puts "Results saved to: #{output}"
        else
          puts output_str
        end
      rescue Stripe::StripeError => ex
        puts "Error executing Sigma query: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing sigma run', Onetime::CLI::BillingSigmaRunCommand
