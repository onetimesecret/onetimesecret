# frozen_string_literal: true

require 'onetime/helpers/session_helpers'

module Billing
  module Controllers
    module Base
      include Onetime::LoggerMethods
      include Onetime::Helpers::SessionHelpers

      attr_reader :req, :res, :locale, :region

      def initialize(req, res)
        @req    = req
        @res    = res
        @locale = req.locale
        @region = OT.conf&.dig('site', 'regions', 'current_jurisdiction') || 'LL'

        # Self-healing: Ensure customer has a default workspace
        # This is a background operation - errors are logged but not surfaced to the user
        # since this is not the result of an intentional user action but system self-healing
        ensure_customer_has_workspace
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

      # Detect region from request
      #
      # @return [String] Region code (default: 'LL')
      def detect_region
        # For Phase 1, default to the configured jurisdiction
        # Future: Use req.env['HTTP_CF_IPCOUNTRY'] or GeoIP database
        region
      end

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

      # Ensures customer has a default workspace (self-healing operation)
      #
      # This method is called automatically on billing overview access to ensure
      # every customer has at least one organization. If the customer doesn't have
      # an organization, we create a default one automatically.
      #
      # This is a self-healing operation - any errors are logged but NOT surfaced
      # to the user since this is not the result of an intentional user action.
      #
      # @return [void]
      def ensure_customer_has_workspace
        billing_logger.debug "[ensure_customer_has_workspace] Checking customer workspace"
        return if cust.anonymous?

        # Use Familia v2 auto-generated reverse collection method for O(1) lookup
        return if cust.organization_instances.any?

        billing_logger.info "[self-healing] Customer has no organization, creating default workspace", {
          custid: cust.custid
        }

        # Call CreateDefaultWorkspace operation
        require_relative '../../auth/operations/create_default_workspace'
        result = Auth::Operations::CreateDefaultWorkspace.new(customer: cust).call

        if result
          billing_logger.info "[self-healing] Successfully created default workspace", {
            custid: cust.custid,
            orgid: result[:organization]&.orgid,
            teamid: result[:team]&.teamid
          }
        end

      rescue StandardError => ex
        # Errors are logged but NOT raised - this is a self-healing operation
        # The user experience should continue even if workspace creation fails
        billing_logger.error "[self-healing] Failed to create default workspace", {
          exception: ex,
          custid: cust.custid,
          message: ex.message,
          backtrace: ex.backtrace&.first(5)
        }
      end

      # Load organization and verify ownership/membership
      #
      # @param orgid [String] Organization identifier
      # @param require_owner [Boolean] If true, require current user to be owner
      # @return [Onetime::Organization] Loaded organization
      # @raise [OT::Problem] If organization not found or access denied
      def load_organization(extid, require_owner: false)
        org = Onetime::Organization.find_by_extid(extid)
        raise OT::Problem, "Organization not found" unless org

        unless org.member?(cust)
          billing_logger.warn "Access denied to organization", {
            extid: extid,
            custid: cust.custid
          }
          raise OT::Problem, "Access denied"
        end

        if require_owner && !org.owner?(cust)
          billing_logger.warn "Owner access required", {
            extid: extid,
            custid: cust.custid
          }
          raise OT::Problem, "Owner access required"
        end

        org
      end
    end

    class TeaPot
      include Base

      def brew
        res.status = 418
        { message: "I'm a teapot" }
      end
    end
  end
end
