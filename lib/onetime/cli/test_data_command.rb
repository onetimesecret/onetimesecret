# lib/onetime/cli/test_data_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    class TestDataCommand < Command
      desc 'Create or cleanup test data for a customer'

      argument :email, type: :string, required: true, desc: 'Customer email address'

      option :org_name,
        type: :string,
        default: nil,
        desc: 'Organization name (default: auto-generated)'

      option :cleanup,
        type: :boolean,
        default: false,
        desc: 'Remove all non-default orgs for the user'

      def call(email:, org_name: nil, cleanup: false, **)
        boot_application!

        if cleanup
          cleanup_test_data(email)
        else
          create_test_data(email, org_name)
        end
      end

      private

      def create_test_data(email, org_name)
        # Load customer
        cust = Onetime::Customer.find_by_email(email)
        unless cust
          puts "Error: Customer not found for #{email}"
          exit 1
        end

        puts "Found customer: #{cust.custid} (#{cust.email})"

        # Create non-default organization
        org_display_name = org_name || "#{cust.email.split('@').first.capitalize} Corp"
        contact_email    = "billing-#{Time.now.to_i}@example.com"

        org            = Onetime::Organization.create!(org_display_name, cust, contact_email)
        org.is_default = false  # Make it non-default so it shows in UI
        org.save

        puts "Created organization: #{org.objid} - #{org.display_name}"
        puts "  - is_default: #{org.is_default}"
        puts "  - contact_email: #{org.contact_email}"

        # Summary
        puts ''
        puts '✓ Test data created:'
        puts "  Customer: #{cust.email}"
        puts "  Organization: #{org.display_name} (#{org.objid})"
        puts ''
        puts "Login as #{email} and visit /billing to see the org link!"
      rescue Onetime::Problem => ex
        puts "Error: #{ex.message}"
        exit 1
      rescue StandardError => ex
        puts "Unexpected error: #{ex.message}"
        puts ex.backtrace.first(5)
        exit 1
      end

      def cleanup_test_data(email)
        # Load customer
        cust = Onetime::Customer.find_by_email(email)
        unless cust
          puts "Error: Customer not found for #{email}"
          exit 1
        end

        puts "Cleaning up test data for: #{cust.email}"

        # Remove non-default organizations
        orgs = cust.list_organizations.reject(&:is_default)

        orgs.each do |org|
          puts "Removing organization: #{org.display_name} (#{org.objid})"
          org.destroy!
        end

        puts "✓ Cleaned up #{orgs.size} organization(s) for #{email}"
      rescue Onetime::Problem => ex
        puts "Error: #{ex.message}"
        exit 1
      rescue StandardError => ex
        puts "Unexpected error: #{ex.message}"
        puts ex.backtrace.first(5)
        exit 1
      end
    end

    register 'test-data', TestDataCommand
  end
end
