# lib/onetime/domain_validation/approximated_client.rb
#
# frozen_string_literal: true

require 'httparty'

module Onetime
  module DomainValidation
    # ApproximatedClient - HTTP client for the approximated.app API.
    #
    # Design Decision: Module with class methods using HTTParty.
    #
    # This is extracted from Onetime::Cluster::Approximated. The module pattern
    # with HTTParty is idiomatic Ruby for HTTP clients. Each method is stateless
    # and receives the api_key explicitly, making it easy to test and reason about.
    #
    # All methods that call the approximated.app API live here.
    #
    # Usage:
    #   ApproximatedClient.check_records_exist(api_key, records)
    #   ApproximatedClient.create_vhost(api_key, domain, target, '443')
    #   ApproximatedClient.get_vhost_by_incoming_address(api_key, domain)
    #   ApproximatedClient.delete_vhost(api_key, domain)
    #   ApproximatedClient.get_dns_widget_token(api_key)
    #
    module ApproximatedClient
      include HTTParty

      base_uri 'https://cloud.approximated.app/api'
      headers 'content-type' => 'application/json'

      # Checks the existence of specified DNS records.
      #
      # @param api_key [String] API key for authentication
      # @param records [Array<Hash>] DNS records to check
      #   Each hash: { type: 'A'|'TXT'|etc, address: 'domain', match_against: 'value' }
      #
      # @return [HTTParty::Response] Response with 'records' array containing
      #   'match' (boolean) and 'actual_values' (array) for each record
      #
      # @example
      #   records = [{ type: 'A', address: 'example.com', match_against: '192.0.2.1' }]
      #   response = ApproximatedClient.check_records_exist(api_key, records)
      #   # => { "records" => [{ "match" => true, "actual_values" => ["192.0.2.1"], ... }] }
      #
      def self.check_records_exist(api_key, records)
        post(
          '/dns/check-records-exist',
          headers: { 'api-key' => api_key },
          body: { records: records }.to_json,
        )
      end

      # Checks DNS records with exact match requirement.
      #
      # Unlike check_records_exist, 'match' is only true when there is
      # exactly one DNS record/value that exactly matches match_against.
      #
      # @param api_key [String] API key for authentication
      # @param records [Array<Hash>] DNS records to check
      # @return [HTTParty::Response]
      #
      def self.check_records_match_exactly(api_key, records)
        post(
          '/dns/check-records-match-exactly',
          headers: { 'api-key' => api_key },
          body: { records: records }.to_json,
        )
      end

      # Creates a virtual host for custom domain SSL.
      #
      # @param api_key [String] API key for authentication
      # @param incoming_address [String] Custom domain (e.g., 'secrets.example.com')
      # @param target_address [String] Target backend (e.g., 'app.onetimesecret.com')
      # @param target_ports [String] Target ports (typically '443')
      # @param options [Hash] Optional configuration
      #   @option options [Boolean] :redirect_www (false) Redirect www subdomain
      #   @option options [Boolean] :redirect (false) Redirect traffic
      #   @option options [Boolean] :exact_match (false) Exact domain matching
      #   @option options [Boolean, nil] :keep_host (nil) Keep original Host header
      #
      # @return [HTTParty::Response] Response with 'data' containing vhost details
      # @raise [HTTParty::ResponseError] On 401 (invalid key) or 422 (validation error)
      #
      def self.create_vhost(api_key, incoming_address, target_address, target_ports, options = {})
        default_options = {
          redirect_www: false,
          redirect: false,
          exact_match: false,
          keep_host: nil,
        }
        post_options    = default_options.merge(options)

        response = post(
          '/vhosts',
          headers: { 'api-key' => api_key },
          body: {
            incoming_address: incoming_address,
            target_address: target_address,
            target_ports: target_ports,
            redirect: post_options[:redirect],
            exact_match: post_options[:exact_match],
            redirect_www: post_options[:redirect_www],
            keep_host: post_options[:keep_host],
          }.to_json,
        )

        handle_error_response(response, incoming_address)
        response
      end

      # Retrieves vhost by incoming address.
      #
      # @param api_key [String] API key for authentication
      # @param incoming_address [String] Domain to look up
      # @param force [Boolean] Force re-check (rate limited, can take 30s)
      #
      # @return [HTTParty::Response] Response with 'data' containing:
      #   - status: 'ACTIVE_SSL', 'PENDING', etc.
      #   - has_ssl: boolean
      #   - is_resolving: boolean
      #   - dns_pointed_at: IP address
      #   - status_message: Human-readable status
      #
      # @raise [HTTParty::ResponseError] On 404 (not found) or 401 (invalid key)
      #
      def self.get_vhost_by_incoming_address(api_key, incoming_address, force = false)
        url_path  = "/vhosts/by/incoming/#{incoming_address}"
        url_path += '/force-check' if force

        response = get(url_path, headers: { 'api-key' => api_key })

        case response.code
        when 404
          raise HTTParty::ResponseError, "Could not find Virtual Host: #{incoming_address}"
        when 401
          raise HTTParty::ResponseError, 'Invalid API key'
        end

        response
      end

      # Updates an existing virtual host.
      #
      # @param api_key [String] API key for authentication
      # @param current_incoming_address [String] Current domain of the vhost
      # @param incoming_address [String] New domain (can be same as current)
      # @param target_address [String] New target backend
      # @param target_ports [String] New target ports
      # @param options [Hash] Optional configuration (same as create_vhost)
      #
      # @return [HTTParty::Response]
      # @raise [HTTParty::ResponseError] On 404 or 401
      #
      def self.update_vhost(api_key, current_incoming_address, incoming_address,
                            target_address, target_ports, options = {})
        default_options = {
          redirect_www: true,
          redirect: false,
          exact_match: false,
          keep_host: nil,
        }
        post_options    = default_options.merge(options)

        response = post(
          '/vhosts/update/by/incoming',
          headers: { 'api-key' => api_key },
          body: {
            current_incoming_address: current_incoming_address,
            incoming_address: incoming_address,
            target_address: target_address,
            target_ports: target_ports,
            redirect: post_options[:redirect],
            exact_match: post_options[:exact_match],
            redirect_www: post_options[:redirect_www],
            keep_host: post_options[:keep_host],
          }.to_json,
        )

        case response.code
        when 404
          raise HTTParty::ResponseError,
            "Could not find an existing Virtual Host: #{current_incoming_address}"
        when 401
          raise HTTParty::ResponseError, 'Invalid API key'
        end

        response
      end

      # Deletes a virtual host.
      #
      # @param api_key [String] API key for authentication
      # @param incoming_address [String] Domain of the vhost to delete
      #
      # @return [HTTParty::Response]
      # @raise [HTTParty::ResponseError] On 404 or 401
      #
      def self.delete_vhost(api_key, incoming_address)
        response = delete(
          "/vhosts/by/incoming/#{incoming_address}",
          headers: { 'api-key' => api_key },
        )

        case response.code
        when 404
          raise HTTParty::ResponseError, "Could not find Virtual Host: #{incoming_address}"
        when 401
          raise HTTParty::ResponseError, 'Invalid API key'
        end

        response
      end

      # Retrieves a DNS widget token for client-side DNS management.
      #
      # The widget helps users configure DNS records with provider-specific
      # instructions. Token expires in 10 minutes but auto-renews.
      #
      # @param api_key [String] API key for authentication
      # @return [HTTParty::Response] Response with 'token' field
      # @raise [HTTParty::ResponseError] On 401
      #
      def self.get_dns_widget_token(api_key)
        response = get('/dns/token', headers: { 'api-key' => api_key })

        if response.code == 401
          raise HTTParty::ResponseError, 'Invalid API key'
        end

        response
      end

      # Handle common error responses from the API.
      #
      # @param response [HTTParty::Response]
      # @param context [String] Context for error message
      # @raise [HTTParty::ResponseError]
      #
      private_class_method def self.handle_error_response(response, _context = nil)
        case response.code
        when 422
          raise HTTParty::ResponseError, response.parsed_response['errors']
        when 401
          raise HTTParty::ResponseError, 'Invalid API key'
        end
      end
    end
  end
end
