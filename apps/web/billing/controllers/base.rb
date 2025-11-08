# frozen_string_literal: true

require 'onetime/helpers/session_helpers'

module Billing
  module Controllers
    module Base
      include Onetime::Logging
      include Onetime::Helpers::SessionHelpers

      attr_reader :req, :res, :locale

      def initialize(req, res)
        @req    = req
        @res    = res
        @locale = req.locale
      end

      # Access the current customer from Otto auth middleware or session
      def cust
        @cust ||= load_current_customer
      end

      # Access the current session
      def session
        req.env['rack.session']
      end

      # JSON response helpers
      #
      # These methods return Hash objects that will be serialized by Otto's JSONHandler
      # when the route has response=json. Do not manually set res.body for JSON responses.

      def json_response(data, status: 200)
        res.status = status
        data
      end

      def json_success(message, status: 200)
        json_response({ success: message }, status: status)
      end

      def json_error(message, field_error: nil, status: 400)
        body = { error: message }
        body['field-error'] = field_error if field_error
        json_response(body, status: status)
      end

      protected

      # Validates a given URL and ensures it can be safely redirected to.
      #
      # @param url [String] the URL to validate
      # @return [URI::HTTP, nil] the validated URI object if valid, otherwise nil
      def validate_url(url)
        uri = nil
        begin
          uri = URI.parse(url)
        rescue URI::InvalidURIError => ex
          billing_logger.error "Invalid URI in URL validation", {
            exception: ex,
            url: url
          }
        else
          uri.host ||= OT.conf['site']['host']
          if (OT.conf['site']['ssl']) && (uri.scheme.nil? || uri.scheme != 'https')
            uri.scheme = 'https'
          end
          uri = nil unless uri.is_a?(URI::HTTP)
          OT.info "[validate_url] Validated URI: #{uri}"
        end

        uri
      end

      # Returns the StrategyResult created by Otto's RouteAuthWrapper
      #
      # @return [Otto::Security::Authentication::StrategyResult]
      def strategy_result
        req.env['otto.strategy_result']
      end

      def load_current_customer
        user = req.user
        return user if user.is_a?(Onetime::Customer)

        Onetime::Customer.anonymous
      rescue StandardError => ex
        billing_logger.error "Failed to load customer", {
          exception: ex
        }
        Onetime::Customer.anonymous
      end

      # Checks if the request accepts JSON responses
      #
      # @return [Boolean] True if the Accept header includes application/json
      def json_requested?
        req.env['HTTP_ACCEPT']&.include?('application/json')
      end

      # Load organization and verify ownership/membership
      #
      # @param orgid [String] Organization identifier
      # @param require_owner [Boolean] If true, require current user to be owner
      # @return [Onetime::Organization] Loaded organization
      # @raise [OT::Problem] If organization not found or access denied
      def load_organization(orgid, require_owner: false)
        org = Onetime::Organization.load(orgid)
        raise OT::Problem, "Organization not found" unless org

        unless org.member?(cust)
          billing_logger.warn "Access denied to organization", {
            orgid: orgid,
            custid: cust.custid
          }
          raise OT::Problem, "Access denied"
        end

        if require_owner && !org.owner?(cust)
          billing_logger.warn "Owner access required", {
            orgid: orgid,
            custid: cust.custid
          }
          raise OT::Problem, "Owner access required"
        end

        org
      end

    end
  end
end
