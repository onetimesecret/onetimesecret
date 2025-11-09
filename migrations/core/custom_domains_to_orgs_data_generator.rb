# frozen_string_literal: true

# Data generator for testing CustomDomain custid → org_id migration logic
#
# Usage:
#   require_relative 'custom_domains_to_orgs_data_generator'
#   Onetime::Migration::CustomDomainsToOrgsDataGenerator.generate_test_data
#
module Onetime
  module Migration
    class CustomDomainsToOrgsDataGenerator

      def self.generate_test_data
        OT.info '[DataGen] Generating test data for CustomDomain migration...'

        # Clean slate
        Familia.dbclient.flushdb

        # Use timestamp to ensure unique domains across runs
        timestamp = Familia.now.to_i

        stats = {
          customers: 0,
          organizations: 0,
          domains: 0
        }

        # Scenario 1: Normal customer with domains (3 customers)
        3.times do |i|
          customer = create_customer_with_domains("normal-#{i}-#{timestamp}@test.com", domain_count: 2, timestamp: timestamp)
          stats[:customers] += 1
          stats[:organizations] += customer.organization_instances.size
          stats[:domains] += 2
        end

        # Scenario 2: Customer with many domains (1 customer, 10 domains)
        customer = create_customer_with_domains("heavy-user-#{timestamp}@test.com", domain_count: 10, timestamp: timestamp)
        stats[:customers] += 1
        stats[:organizations] += customer.organization_instances.size
        stats[:domains] += 10

        # Scenario 3: Customer with no domains (2 customers)
        2.times do |i|
          customer = Onetime::Customer.create!(email: "no-domains-#{i}-#{timestamp}@test.com")
          org = Onetime::Organization.create!("Org No Domains #{i}", customer, "org-#{i}-#{timestamp}@test.com")
          stats[:customers] += 1
          stats[:organizations] += 1
        end

        # Scenario 4: Multiple customers in same organization sharing domains
        owner = Onetime::Customer.create!(email: "shared-owner-#{timestamp}@test.com")
        org = Onetime::Organization.create!("Shared Org", owner, "shared-#{timestamp}@test.com")
        member = Onetime::Customer.create!(email: "shared-member-#{timestamp}@test.com")
        org.add_members_instance(member)

        # Create domains in shared org
        2.times do |i|
          domain_input = "shared-#{i}-#{timestamp}.example.com"
          Onetime::CustomDomain.create!(domain_input, org.objid)
        end

        stats[:customers] += 2
        stats[:organizations] += 1
        stats[:domains] += 2

        log_stats(stats)
        stats
      end

      private

      def self.create_customer_with_domains(email, domain_count: 2, timestamp: nil)
        customer = Onetime::Customer.create!(email: email)
        org = Onetime::Organization.create!("Org for #{email}", customer, "org-#{email}")

        domain_count.times do |i|
          # Extract base from email for uniqueness
          base = email.split('@').first
          domain_input = "#{base}-domain-#{i}.example.com"
          Onetime::CustomDomain.create!(domain_input, org.objid)
        end

        customer
      end

      def self.log_stats(stats)
        OT.info '[DataGen] Test data generated:'
        OT.info "  Customers: #{stats[:customers]}"
        OT.info "  Organizations: #{stats[:organizations]}"
        OT.info "  Custom Domains: #{stats[:domains]}"
      end
    end
  end
end
