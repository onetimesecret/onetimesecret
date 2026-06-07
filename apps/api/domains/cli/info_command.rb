# apps/api/domains/cli/info_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Domain info subcommand
    class DomainsInfoCommand < Command
      include DomainsHelpers

      desc 'Show detailed information about a domain'

      argument :identifier, type: :string, required: true, desc: 'Domain name, extid, or objid'

      def call(identifier:, **)
        boot_application!

        domain = load_domain(identifier)
        return unless domain

        puts '=' * 80
        puts "Domain Information: #{domain.display_domain}"
        puts '=' * 80
        puts

        # Basic domain info
        puts 'Domain Details:'
        puts "  Display Domain:       #{domain.display_domain}"
        puts "  Base Domain:          #{domain.base_domain || 'N/A'}"
        puts "  Subdomain:            #{domain.subdomain || 'N/A'}"
        puts "  TLD:                  #{domain.tld || 'N/A'}"
        puts "  SLD:                  #{domain.sld || 'N/A'}"
        puts "  TRD:                  #{domain.trd || 'N/A'}"
        puts

        # Organization ownership
        puts 'Organization Ownership:'
        if domain.org_id.to_s.empty?
          puts '  Status:               ORPHANED (no organization)'
        else
          org = domain.primary_organization
          if org
            owner = org.owner
            puts "  Organization:         #{org.display_name || 'N/A'} (#{org.org_id})"
            puts "  Organization ID:      #{domain.org_id}"
            puts "  Owner Email:          #{owner ? owner.email : 'N/A'}"
            puts "  Member Count:         #{org.member_count}"
          else
            puts "  Organization ID:      #{domain.org_id}"
            puts '  Status:               ORG NOT FOUND (orphaned reference)'
          end
        end
        puts

        # Verification status
        puts 'Verification:'
        puts "  Verified:             #{domain.verified || 'false'}"
        puts "  Resolving:            #{domain.resolving || 'false'}"
        puts "  Verification State:   #{domain.verification_state}"
        puts "  Status:               #{domain.status || 'N/A'}"
        puts

        # DNS records
        puts 'DNS Configuration:'
        puts "  TXT Validation Host:  #{domain.txt_validation_host || 'N/A'}"
        puts "  TXT Validation Value: #{domain.txt_validation_value || 'N/A'}"
        puts "  Validation Record:    #{domain.validation_record || 'N/A'}"
        puts

        # Domain attributes
        puts 'Domain Attributes:'
        puts "  Apex Domain:          #{domain.apex? || 'false'}"
        puts

        # Per-domain feature toggles (#3026: HomepageConfig / ApiConfig, not brand)
        puts 'Feature Toggles:'
        puts "  Allow Public Home:    #{domain.allow_public_homepage? || 'false'}"
        puts "  Allow Public API:     #{domain.allow_public_api? || 'false'}"
        puts

        # Vhost (Approximated) details
        puts 'Vhost (Approximated):'
        vhost_data = domain.parse_vhost
        if vhost_data.nil? || vhost_data.empty?
          puts '  (not set)'
        else
          vhost_data.each do |key, value|
            puts format('  %-20s %s', "#{key}:", value.to_s)
          end
        end
        puts

        # Timestamps
        puts 'Timestamps:'
        puts "  Created:              #{format_timestamp(domain.created)}"
        puts "  Updated:              #{format_timestamp(domain.updated)}"
        puts

        # Internal identifiers
        puts 'Internal:'
        puts "  Object ID (objid):    #{domain.objid}"
        puts "  External ID (extid):  #{domain.extid}"
        puts "  Domain ID:            #{domain.domainid}"
        puts "  DB Key:               #{domain.dbkey}"
        puts
      end
    end
  end
end

Onetime::CLI.register 'domains info', Onetime::CLI::DomainsInfoCommand
Onetime::CLI.register 'domains show', Onetime::CLI::DomainsInfoCommand
