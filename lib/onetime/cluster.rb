require 'httparty'

module Onetime
  module Cluster

    # Onetime::Cluster::Approximated is a utility class for comunicating with
    # the approximated.app API.
    #
    # It uses the HTTParty gem to make HTTP requests.
    #
    class Approximated
      include HTTParty
      base_uri 'https://cloud.approximated.app/api'
      headers 'Content-Type' => 'application/json'

      # Checks the existence of specified DNS records.
      #
      # @param api_key [String] The API key for authenticating with the Approximated API.
      # @param records [Array<Hash>] An array of hashes representing DNS records to check.
      #   Each hash should contain keys like 'type', 'name', and 'value'.
      #
      # @return [HTTParty::Response] The response from the API call.
      #
      # @example
      #   api_key = 'your_api_key_here'
      #   records = [
      #     { type: 'A', name: 'example.com', value: '192.0.2.1' },
      #     { type: 'MX', name: 'example.com', value: 'mail.example.com' }
      #   ]
      #   response = Approximated.check_records(api_key, records)
      #
      def self.check_records_exist(api_key, records)
        post('/dns/check-records-exist',
          headers: { 'api-key' => api_key },
          body: { records: records }.to_json)
      end

      # Creates a virtual host using the Approximated API.
      #
      # @param api_key [String] The API key for authenticating with the Approximated API.
      # @param incoming_address [String] The custom domain for the virtual host.
      # @param target_address [String] The target address where traffic will be directed.
      # @param target_ports [String] The target ports to use.
      # @param options [Hash] Optional parameters for configuring the virtual host.
      #   @option options [Boolean] :redirect_www (false) Whether to redirect www subdomain.
      #   @option options [Boolean] :redirect (false) Whether to redirect traffic.
      #   @option options [Boolean] :exact_match (false) Whether to use exact matching for the domain.
      #   @option options [Boolean, nil] :keep_host (nil) Whether to keep the original host header.
      #
      # @return [HTTParty::Response] The response from the API call.
      #
      # Recommended user message: In order to connect your domain, you'll need to have
      # a DNS A record that points 72.tryouts.onetimesecret.com at 213.188.207.78. If
      # you already have an A record for that address, please change it to point at
      # 213.188.207.78 and remove any other A, AAAA, or CNAME records for that exact
      # address. It may take a few minutes for your SSL certificate to take effect
      # once you've pointed your DNS A record.
      #
      # @example
      #   api_key = 'your_api_key_here'
      #   incoming_address = 'custom.example.com'
      #   target_address = 'app.example.com'
      #   target_ports = '443'
      #   options = { redirect: true, exact_match: true }
      #   response = Approximated.create_vhost(api_key, incoming_address, target_address, target_ports, options)
      #
      def self.create_vhost(
        api_key,
        incoming_address,
        target_address,
        target_ports,
        options = {}
      )
        default_options = {
          redirect_www: false,
          redirect: false,
          exact_match: false,
          keep_host: nil
        }
        post_options = default_options.merge(options)

        response = post('/vhosts',
          headers: { 'api-key' => api_key },
          body: {
            incoming_address: incoming_address,
            target_address: target_address,
            target_ports: target_ports,
            redirect: post_options[:redirect],
            exact_match: post_options[:exact_match],
            redirect_www: post_options[:redirect_www],
            keep_host: post_options[:keep_host]
          }.to_json)

        case response.code
        when 422
          raise HTTParty::ResponseError, response.parsed_response['errors']
        when 401
          raise HTTParty::ResponseError, "Invalid API key"
        end

        response
      end

      # Retrieves a virtual host by its incoming address.
      #
      # @param api_key [String] The API key for authenticating with the Approximated API.
      # @param incoming_address [String] The incoming address of the virtual host to retrieve.
      #
      # @return [HTTParty::Response] The response from the API call.
      #
      # @example
      #   api_key = 'your_api_key_here'
      #   incoming_address = 'custom.example.com'
      #   response = Approximated.get_vhost_by_incoming_address(api_key, incoming_address)
      #
      # @raise [HTTParty::ResponseError] If the API returns a 404 (Virtual Host not found) or 401 (Invalid API key) error.
      #
      def self.get_vhost_by_incoming_address(api_key, incoming_address)
        response = get("/vhosts/by/incoming/#{incoming_address}",
          headers: { 'api-key' => api_key })

        case response.code
        when 404
          raise HTTParty::ResponseError, "Could not find Virtual Host: #{incoming_address}"
        when 401
          raise HTTParty::ResponseError, "Invalid API key"
        end

        response
      end

      # Updates an existing virtual host using the Approximated API.
      #
      # @param api_key [String] The API key for authenticating with the Approximated API.
      # @param current_incoming_address [String] The current incoming address of the virtual host to update.
      # @param incoming_address [String] The new custom domain for the virtual host.
      # @param target_address [String] The target address where traffic will be directed.
      # @param target_ports [String] The target ports to use.
      # @param options [Hash] Optional parameters for configuring the virtual host.
      #   @option options [Boolean] :redirect_www (true) Whether to redirect www subdomain.
      #   @option options [Boolean] :redirect (false) Whether to redirect traffic.
      #   @option options [Boolean] :exact_match (false) Whether to use exact matching for the domain.
      #   @option options [Boolean, nil] :keep_host (nil) Whether to keep the original host header.
      #
      # @return [HTTParty::Response] The response from the API call.
      #
      # @example
      #   api_key = 'your_api_key_here'
      #   current_incoming_address = 'old.example.com'
      #   incoming_address = 'new.example.com'
      #   target_address = 'app.example.com'
      #   target_ports = '443'
      #   options = { redirect: true, exact_match: true }
      #   response = Approximated.update_vhost(api_key, current_incoming_address, incoming_address, target_address, target_ports, options)
      #
      # @raise [HTTParty::ResponseError] If the API returns a 404 (Virtual Host not found) or 401 (Invalid API key) error.
      #
      def self.update_vhost(
        api_key,
        current_incoming_address,
        incoming_address,
        target_address,
        target_ports,
        options = {}
      )
        default_options = {
          redirect_www: true,
          redirect: false,
          exact_match: false,
          keep_host: nil
        }
        post_options = default_options.merge(options)

        response = post('/vhosts/update/by/incoming',
          headers: { 'api-key' => api_key },
          body: {
            current_incoming_address: current_incoming_address,
            incoming_address: incoming_address,
            target_address: target_address,
            target_ports: target_ports,
            redirect: post_options[:redirect],
            exact_match: post_options[:exact_match],
            redirect_www: post_options[:redirect_www],
            keep_host: post_options[:keep_host]
          }.to_json)

        case response.code
        when 404
          raise HTTParty::ResponseError, "Could not find an existing Virtual Host: #{current_incoming_address}"
        when 401
          raise HTTParty::ResponseError, "Invalid API key"
        end

        response
      end

      # Deletes an existing virtual host using the Approximated API.
      #
      # @param api_key [String] The API key for authenticating with the Approximated API.
      # @param incoming_address [String] The incoming address of the virtual host to delete.
      #
      # @return [HTTParty::Response] The response from the API call.
      #
      # @example
      #   api_key = 'your_api_key_here'
      #   incoming_address = 'customdomain.com'
      #   response = Approximated.delete_vhost(api_key, incoming_address)
      #
      # @raise [HTTParty::ResponseError] If the API returns a 404 (Virtual Host not found) or 401 (Invalid API key) error.
      #
      def self.delete_vhost(api_key, incoming_address)
        response = delete("/vhosts/by/incoming/#{incoming_address}",
          headers: { 'api-key' => api_key })

        case response.code
        when 200
          puts "Successfully deleted Virtual Host: #{incoming_address}"
        when 404
          raise HTTParty::ResponseError, "Could not find Virtual Host: #{incoming_address}"
        when 401
          raise HTTParty::ResponseError, "Invalid API key"
        end

        response
      end
    end

  end
end
