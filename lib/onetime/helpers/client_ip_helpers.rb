# lib/onetime/helpers/client_ip_helpers.rb
#
# frozen_string_literal: true

module Onetime
  # Forwarded header parsing utilities.
  #
  # Provides methods to extract IP addresses from X-Forwarded-For and
  # RFC 7239 Forwarded headers. Used by HomepageModeHelpers for CIDR-based
  # homepage mode detection.
  #
  # For standard IP resolution, use Rack::Request#ip which is configured
  # at boot time via ConfigureTrustedProxy initializer.
  #
  module ClientIpHelpers
    # Parse forwarded IPs from the appropriate request header.
    #
    # @param env         [Hash]   Rack environment
    # @param header_type [String] 'X-Forwarded-For', 'Forwarded', or 'Both'
    # @return [Array<String>, nil]
    def self.extract_forwarded_ips(env, header_type)
      case header_type
      when 'Forwarded'
        extract_rfc7239_forwarded(env)
      when 'Both'
        extract_rfc7239_forwarded(env) || extract_x_forwarded_for(env)
      else
        extract_x_forwarded_for(env)
      end
    end

    # @param env [Hash] Rack environment
    # @return [Array<String>, nil]
    def self.extract_x_forwarded_for(env)
      val = env['HTTP_X_FORWARDED_FOR']
      return nil if val.nil? || val.empty?

      val.split(',').map(&:strip).reject(&:empty?)
    end

    # @param env [Hash] Rack environment
    # @return [Array<String>, nil]
    def self.extract_rfc7239_forwarded(env)
      val = env['HTTP_FORWARDED']
      return nil if val.nil? || val.empty?

      ips = []
      val.split(',').each do |segment|
        segment.split(';').each do |param|
          next unless param.strip =~ /^for=(.+)$/i

          ip = ::Regexp.last_match(1).gsub(/^["']|["']$/, '').gsub(/^\[|\]$/, '')
          ips << ip unless ip.empty?
        end
      end

      ips.empty? ? nil : ips
    end
  end
end
