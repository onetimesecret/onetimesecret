# lib/onetime/cli/domains/probe_command.rb
#
# frozen_string_literal: true

# HTTPS probe of a custom domain — the CLI peer of
# `GET /api/colonel/domains/:extid/probe`. Both adapters call the same op
# (Onetime::Operations::Domains::Probe), which owns the request, the TLS
# inspection and the health taxonomy.
#
# Usage:
#   bin/ots domains probe example.com
#   bin/ots domains probe example.com --json
#   bin/ots domains probe example.com --timeout 30
#   bin/ots domains probe cd123abc --insecure       # debugging only
#
# DOMAIN accepts the display domain (preferred), the domain extid, or its objid.
#
# EXIT CODES: an unhealthy domain is still a successful probe — `dns_error` is
# an answer, not a command failure — so the command exits 0 whatever the health
# verdict. Only failing to RESOLVE the domain exits 1. A monitor that wants to
# alert on health pipes the JSON: `... --json | jq -e '.health == "healthy"'`.
#
# The op records NO AdminAuditEvent: a probe reaches the network but mutates
# nothing in our data store (CONTRACT 4 — audit is for mutations).
#
# Two deliberate asymmetries with the colonel adapter:
#   - --timeout is NOT clamped here. The colonel's MAX_TIMEOUT=30 exists to stop
#     an HTTP request hanging a web worker; a shell has no such constraint.
#   - --insecure is CLI-only. The colonel hardcodes `insecure: false` and must
#     stay that way.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/probe'

module Onetime
  module CLI
    class DomainsProbeCommand < Command
      include Domains::Shared

      desc 'Make HTTPS request to verify domain serves traffic'

      argument :domain,
        type: :string,
        required: true,
        desc: 'Domain to probe (display domain, extid, or objid)'

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

      def call(domain:, timeout: 10, json: false, insecure: false, **)
        boot_application!

        target  = resolve_domain(domain, json: json)
        seconds = coerce_timeout(timeout, json: json)

        # Delegate the probe to the single op implementation (read-only, no
        # audit). The op returns the SAME result Hash the CLI previously built
        # inline, and the colonel wraps the identical fields — the key set is a
        # parity contract. Do not reshape it.
        result = Onetime::Operations::Domains::Probe.new(
          hostname: target.display_domain,
          timeout: seconds,
          insecure: insecure,
        ).call

        OT.info "[cli-domains-probe] domain=#{target.display_domain} health=#{result[:health]}"

        if json
          puts JSON.pretty_generate(result)
        else
          display_probe_result(target, result)
        end
      end

      private

      # dry-cli 1.4.1 does NOT coerce `type: :integer` — Option#parser_options
      # never hands OptionParser an Integer class, so an explicit `--timeout 30`
      # arrives as the String "30" while the declared default stays an Integer.
      # A String reaches Net::HTTP#open_timeout= and then blows up inside
      # IO.select, so coerce (and reject garbage) at the adapter boundary.
      #
      # Deliberately NOT clamped to an upper bound: the colonel's MAX_TIMEOUT=30
      # exists to stop an HTTP request hanging a web worker, and a shell has no
      # such constraint.
      def coerce_timeout(value, json:)
        seconds = Integer(value)
        error_exit('--timeout must be a positive number of seconds', json: json) unless seconds.positive?
        seconds
      rescue ArgumentError, TypeError
        error_exit("--timeout must be an integer (got #{value.inspect})", json: json)
      end

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

    register 'domains probe', DomainsProbeCommand
  end
end
