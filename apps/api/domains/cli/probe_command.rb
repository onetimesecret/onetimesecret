# apps/api/domains/cli/probe_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'net/http'
require 'openssl'
require 'json'

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

        result = probe_domain(domain.display_domain, timeout, insecure)

        if json
          puts JSON.pretty_generate(result)
        else
          display_probe_result(domain, result)
        end
      end

      private

      def probe_domain(hostname, timeout, insecure)
        result = {
          timestamp: Time.now.utc.iso8601,
          domain: hostname,
          url: "https://#{hostname}",
        }

        begin
          uri  = URI.parse("https://#{hostname}")
          http = build_http_client(uri, timeout, insecure)
          cert = nil

          response = http.start do |client|
            # Capture cert while connection is open
            cert                  = client.peer_cert
            request               = Net::HTTP::Get.new(uri.request_uri)
            request['User-Agent'] = 'OTS-Domain-Probe/1.0'
            client.request(request)
          end

          result[:http] = {
            status_code: response.code.to_i,
            status_message: response.message,
            success: response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection),
          }

          result[:ssl]    = extract_ssl_info_from_cert(cert)
          result[:health] = determine_health(result)
        rescue OpenSSL::SSL::SSLError => ex
          result[:http]   = { error: 'SSL Error', message: ex.message }
          result[:ssl]    = { valid: false, error: ex.message }
          result[:health] = 'ssl_error'
        rescue Errno::ECONNREFUSED => ex
          result[:http]   = { error: 'Connection Refused', message: ex.message }
          result[:health] = 'connection_refused'
        rescue Errno::ECONNRESET => ex
          result[:http]   = { error: 'Connection Reset', message: ex.message }
          result[:health] = 'connection_reset'
        rescue Net::OpenTimeout, Net::ReadTimeout => ex
          result[:http]   = { error: 'Timeout', message: ex.message }
          result[:health] = 'timeout'
        rescue SocketError => ex
          result[:http]   = { error: 'DNS Resolution Failed', message: ex.message }
          result[:health] = 'dns_error'
        rescue StandardError => ex
          result[:http]   = { error: ex.class.name, message: ex.message }
          result[:health] = 'error'
        end

        result
      end

      def build_http_client(uri, timeout, insecure)
        http              = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = true
        http.open_timeout = timeout
        http.read_timeout = timeout

        http.verify_mode = if insecure
          OpenSSL::SSL::VERIFY_NONE
        else
          OpenSSL::SSL::VERIFY_PEER
                           end

        http
      end

      def extract_ssl_info_from_cert(cert)
        return { valid: false, error: 'No certificate' } unless cert

        now               = Time.now
        not_before        = cert.not_before
        not_after         = cert.not_after
        days_until_expiry = ((not_after - now) / 86_400).to_i

        {
          valid: true,
          subject: cert.subject.to_s,
          issuer: cert.issuer.to_s,
          not_before: not_before.iso8601,
          not_after: not_after.iso8601,
          days_until_expiry: days_until_expiry,
          expired: now > not_after,
          not_yet_valid: now < not_before,
        }
      rescue StandardError => ex
        { valid: false, error: ex.message }
      end

      def determine_health(result)
        http = result[:http]
        ssl  = result[:ssl]

        return 'error' if http[:error]
        return 'ssl_invalid' unless ssl[:valid]
        return 'ssl_expired' if ssl[:expired]
        return 'ssl_expiring_soon' if ssl[:days_until_expiry] && ssl[:days_until_expiry] < 7

        if http[:success]
          'healthy'
        else
          'http_error'
        end
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
  end
end

Onetime::CLI.register 'domains probe', Onetime::CLI::DomainsProbeCommand
