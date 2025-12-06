# apps/api/domains/cli/helpers.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Base module for domain command helpers
    module DomainsHelpers
      def apply_filters(domains, orphaned: false, org_id: nil, verified: false, unverified: false)
        filtered = domains

        # Filter by orphaned status
        if orphaned
          filtered = filtered.select { |d| d.org_id.to_s.empty? }
        end

        # Filter by organization
        if org_id
          filtered = filtered.select { |d| d.org_id.to_s == org_id.to_s }
        end

        # Filter by verification status
        if verified
          filtered = filtered.select { |d| d.verified.to_s == 'true' }
        elsif unverified
          filtered = filtered.reject { |d| d.verified.to_s == 'true' }
        end

        filtered
      end

      def format_domain_row(domain)
        org_info = get_organization_info(domain)
        status   = domain.verification_state || 'unknown'
        verified = domain.verified.to_s == 'true' ? 'yes' : 'no'

        format('%-40s %-30s %-12s %-10s',
          domain.display_domain[0..39],
          org_info[0..29],
          status[0..11],
          verified,
        )
      end

      def get_organization_info(domain)
        if domain.org_id.to_s.empty?
          'ORPHANED'
        else
          org = domain.primary_organization
          if org
            "#{org.display_name || org.org_id}"
          else
            "ORG NOT FOUND (#{domain.org_id[0..10]})"
          end
        end
      end

      def load_domain_by_name(domain_name)
        domain = Onetime::CustomDomain.load_by_display_domain(domain_name)
        unless domain
          puts "Error: Domain '#{domain_name}' not found"
          return nil
        end
        domain
      end

      def load_organization(org_id, silent: false)
        org = Onetime::Organization.load(org_id)
        unless org
          puts "Error: Organization '#{org_id}' not found" unless silent
          return nil
        end
        org
      end

      def format_timestamp(timestamp)
        return 'N/A' unless timestamp

        Time.at(timestamp.to_i).strftime('%Y-%m-%d %H:%M:%S UTC')
      rescue StandardError
        'invalid'
      end
    end
  end
end
