# apps/api/domains/cli/probe_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'json'
require 'onetime/operations/domains/probe'

module Onetime
  module CLI
    # HTTP probe to verify domain serves traffic
    class DomainsProbeCommand < Command
      include DomainsHelpers

      desc 'Make HTTPS request to verify domain serves traffic'

      argument :domain_name, type: :string, required: true, desc: 'Domain name to probe'

      option :timeout,
        type: :integer,
        default: 10,
        desc: 'Request timeout in seconds'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON for scripting'

      option :insecure,
        type: :boolean,
        default: false,
        desc: 'Skip SSL certificate verification (for debugging)'

      def call(domain_name:, timeout: 10, json: false, insecure: false, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        # Delegate the probe to the single op implementation (read-only, no audit).
        # The op returns the SAME result Hash the CLI previously built inline, so
        # the --json output is byte-identical.
        result = Onetime::Operations::Domains::Probe.new(
          hostname: domain.display_domain,
          timeout: timeout,
          insecure: insecure,
        ).call

        if json
          puts JSON.pretty_generate(result)
        else
          display_probe_result(domain, result)
        end
      end

      private

      def display_probe_result(domain, result)
        puts '=' * 80
        puts "Domain Probe: #{domain.display_domain}"
        puts '=' * 80
        puts

        puts "Timestamp:          #{result[:timestamp]}"
        puts "URL:                #{result[:url]}"
        puts

        display_http_result(result[:http])
        display_ssl_result(result[:ssl])
        display_health_assessment(result[:health])
      end

      def display_http_result(http)
        puts 'HTTP Response:'
        if http[:error]
          puts "  Error:              #{http[:error]}"
          puts "  Message:            #{http[:message]}"
        else
          puts "  Status:             #{http[:status_code]} #{http[:status_message]}"
          puts "  Success:            #{http[:success]}"
        end
        puts
      end

      def display_ssl_result(ssl)
        puts 'SSL Certificate:'
        if ssl.nil?
          puts '  Not available'
        elsif ssl[:error]
          puts '  Valid:              false'
          puts "  Error:              #{ssl[:error]}"
        else
          puts "  Valid:              #{ssl[:valid]}"
          puts "  Subject:            #{ssl[:subject]}"
          puts "  Issuer:             #{ssl[:issuer]}"
          puts "  Not Before:         #{ssl[:not_before]}"
          puts "  Not After:          #{ssl[:not_after]}"
          puts "  Days Until Expiry:  #{ssl[:days_until_expiry]}"
          puts "  Expired:            #{ssl[:expired]}"
        end
        puts
      end

      def display_health_assessment(health)
        puts 'Health Assessment:'
        status_label = case health
                       when 'healthy'
                         'HEALTHY'
                       when 'ssl_expiring_soon'
                         'WARNING - SSL expiring soon'
                       when 'ssl_expired'
                         'CRITICAL - SSL expired'
                       when 'ssl_error', 'ssl_invalid'
                         'CRITICAL - SSL issue'
                       when 'timeout'
                         'CRITICAL - Request timeout'
                       when 'dns_error'
                         'CRITICAL - DNS resolution failed'
                       when 'connection_refused', 'connection_reset'
                         'CRITICAL - Connection failed'
                       else
                         "ERROR - #{health}"
                       end
        puts "  Status:             #{status_label}"
        puts
      end
    end
  end
end

Onetime::CLI.register 'domains probe', Onetime::CLI::DomainsProbeCommand
