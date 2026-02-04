# apps/api/domains/cli/check_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'json'

module Onetime
  module CLI
    # Single domain health check
    class DomainsCheckCommand < Command
      include DomainsHelpers

      desc 'Show comprehensive health for a single domain'

      argument :domain_name, type: :string, required: true, desc: 'Domain name to check'

      option :refresh,
        type: :boolean,
        default: false,
        desc: 'Perform live DNS/SSL validation checks'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON for scripting'

      def call(domain_name:, refresh: false, json: false, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        strategy = get_validation_strategy
        result   = build_check_result(domain, strategy, refresh)

        if json
          puts JSON.pretty_generate(result)
        else
          display_check_result(domain, result, strategy, refresh)
        end
      end

      private

      def build_check_result(domain, strategy, refresh)
        result = {
          timestamp: Time.now.utc.iso8601,
          domain: domain.display_domain,
          strategy: strategy.strategy_name,
          live_checks: refresh && strategy.manages_certificates?,
          stored_state: {
            verification_state: domain.verification_state.to_s,
            verified: domain.verified.to_s == 'true',
            resolving: domain.resolving.to_s == 'true',
            ready: domain.ready?,
          },
          organization: build_organization_result(domain),
          brand: {
            allow_public_homepage: domain.allow_public_homepage?,
            allow_public_api: domain.allow_public_api?,
          },
        }

        if refresh && strategy.manages_certificates?
          result[:live_dns] = perform_dns_check(strategy, domain)
          result[:live_ssl] = perform_ssl_check(strategy, domain)
        end

        result
      end

      def build_organization_result(domain)
        if domain.org_id.to_s.empty?
          { status: 'ORPHANED', org_id: nil, display_name: nil }
        else
          org = domain.primary_organization
          if org
            {
              status: 'OK',
              org_id: org.org_id,
              display_name: org.display_name || org.org_id,
            }
          else
            { status: 'ORG_NOT_FOUND', org_id: domain.org_id, display_name: nil }
          end
        end
      end

      def perform_dns_check(strategy, domain)
        result = strategy.validate_ownership(domain)
        {
          validated: result[:validated],
          message: result[:message],
        }
      rescue StandardError => ex
        { validated: false, message: "Error: #{ex.message}" }
      end

      def perform_ssl_check(strategy, domain)
        result = strategy.check_status(domain)
        {
          ready: result[:ready],
          status: result[:status],
          has_ssl: result[:has_ssl],
          is_resolving: result[:is_resolving],
          message: result[:message] || result[:status_message],
        }
      rescue StandardError => ex
        { ready: false, message: "Error: #{ex.message}" }
      end

      def display_check_result(domain, result, strategy, refresh)
        puts '=' * 80
        puts "Domain Health Check: #{domain.display_domain}"
        puts '=' * 80
        puts

        puts "Timestamp:          #{result[:timestamp]}"
        puts "Strategy:           #{strategy.strategy_name} (live checks: #{strategy.manages_certificates?})"
        puts

        display_stored_state(result[:stored_state])
        display_organization(result[:organization])
        display_brand_settings(result[:brand])

        return unless refresh

        if strategy.manages_certificates?
          display_live_checks(result)
        else
          puts 'Live Checks:'
          puts '  Skipped:            Strategy does not support live checks'
          puts '  Note:               PassthroughStrategy returns assumed-true values'
          puts
        end
      end

      def display_stored_state(state)
        puts 'Stored Verification State:'
        puts "  State:              #{state[:verification_state].upcase}"
        puts "  Verified:           #{state[:verified]}"
        puts "  Resolving:          #{state[:resolving]}"
        puts "  Ready:              #{state[:ready]}"
        puts
      end

      def display_organization(org)
        puts 'Organization:'
        puts "  Status:             #{org[:status]}"
        if org[:status] == 'OK'
          puts "  Org ID:             #{org[:org_id]}"
          puts "  Display Name:       #{org[:display_name]}"
        elsif org[:status] == 'ORG_NOT_FOUND'
          puts "  Org ID:             #{org[:org_id]} (MISSING)"
        end
        puts
      end

      def display_brand_settings(brand)
        puts 'Brand Settings:'
        puts "  Public Homepage:    #{brand[:allow_public_homepage]}"
        puts "  Public API:         #{brand[:allow_public_api]}"
        puts
      end

      def display_live_checks(result)
        puts 'Live DNS Check:'
        dns = result[:live_dns]
        puts "  Validated:          #{dns[:validated]}"
        puts "  Message:            #{dns[:message]}" if dns[:message]
        puts

        puts 'Live SSL Check:'
        ssl = result[:live_ssl]
        puts "  Ready:              #{ssl[:ready]}"
        puts "  Status:             #{ssl[:status]}" if ssl[:status]
        puts "  Has SSL:            #{ssl[:has_ssl]}" unless ssl[:has_ssl].nil?
        puts "  Is Resolving:       #{ssl[:is_resolving]}" unless ssl[:is_resolving].nil?
        puts "  Message:            #{ssl[:message]}" if ssl[:message]
        puts
      end
    end
  end
end

Onetime::CLI.register 'domains check', Onetime::CLI::DomainsCheckCommand
