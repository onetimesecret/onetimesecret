# lib/onetime/cli/test_data_command.rb
#
# frozen_string_literal: true

module Onetime
  class TestDataCommand < Onetime::CLI
    def test_data
      email = argv.shift
      unless email
        puts 'Usage: ots test-data [options] EMAIL'
        puts ''
        puts 'Options:'
        puts '  --org-name NAME       Organization name (default: auto-generated)'
        puts '  --team-name NAME      Team name (default: auto-generated)'
        puts '  --cleanup             Remove all non-default orgs/teams for the user'
        puts ''
        puts 'Examples:'
        puts '  ots test-data user@example.com'
        puts '  ots test-data --org-name "ACME Corp" user@example.com'
        puts '  ots test-data --cleanup user@example.com'
        exit 1
      end

      if option.cleanup
        cleanup_test_data(email)
      else
        create_test_data(email)
      end
    end

    private

    def create_test_data(email)
      # Load customer
      cust = Onetime::Customer.load_from_email(email)
      unless cust
        puts "Error: Customer not found for #{email}"
        exit 1
      end

      puts "Found customer: #{cust.custid} (#{cust.email})"

      # Create non-default organization
      org_display_name = option.org_name || "#{cust.email.split('@').first.capitalize} Corp"
      contact_email = "billing-#{Time.now.to_i}@example.com"

      org = Onetime::Organization.create!(org_display_name, cust, contact_email)
      org.is_default = false  # Make it non-default so it shows in UI
      org.save

      puts "Created organization: #{org.orgid} - #{org.display_name}"
      puts "  - is_default: #{org.is_default}"
      puts "  - contact_email: #{org.contact_email}"

      # Create team in organization
      team_display_name = option.team_name || "#{org_display_name} Team"
      team = Onetime::Team.create!(team_display_name, cust, org.objid)

      puts "Created team: #{team.teamid} - #{team.display_name}"
      puts "  - org_id: #{team.org_id}"
      puts "  - owner: #{team.owner_id}"

      # Summary
      puts ''
      puts '✓ Test data created:'
      puts "  Customer: #{cust.email}"
      puts "  Organization: #{org.display_name} (#{org.orgid})"
      puts "  Team: #{team.display_name} (#{team.teamid})"
      puts ''
      puts "Login as #{email} and visit /billing to see the org link!"

    rescue Onetime::Problem => e
      puts "Error: #{e.message}"
      exit 1
    rescue StandardError => e
      puts "Unexpected error: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end

    def cleanup_test_data(email)
      # Load customer
      cust = Onetime::Customer.load_from_email(email)
      unless cust
        puts "Error: Customer not found for #{email}"
        exit 1
      end

      puts "Cleaning up test data for: #{cust.email}"

      # Remove non-default organizations
      orgs = cust.list_organizations.reject(&:is_default)

      orgs.each do |org|
        puts "Removing organization: #{org.display_name} (#{org.orgid})"

        # Remove teams first
        org.teams.each do |team_id|
          team = Onetime::Team.load(team_id)
          next unless team
          puts "  Removing team: #{team.display_name}"
          team.destroy!
        end

        org.destroy!
      end

      puts "✓ Cleaned up #{orgs.size} organization(s) for #{email}"

    rescue Onetime::Problem => e
      puts "Error: #{e.message}"
      exit 1
    rescue StandardError => e
      puts "Unexpected error: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end
  end
end
