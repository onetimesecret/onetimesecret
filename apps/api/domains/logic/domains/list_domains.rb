# apps/api/domains/logic/domains/list_domains.rb
#
# frozen_string_literal: true

require_relative '../base'

module DomainsAPI::Logic
  module Domains
    # List domains for an organization
    #
    # Supports two modes:
    # 1. Default: Uses organization from session context
    # 2. Explicit: Uses org_id param (must be an org the user is a member of)
    #
    # The explicit mode allows the frontend to fetch domains for a specific
    # organization when the user switches organizations in the UI, before
    # the session is updated.
    #
    class ListDomains < DomainsAPI::Logic::Base
      attr_reader :custom_domains, :with_brand, :target_organization

      def process_params
        @with_brand   = !params['with_brand'].to_s.empty?
        @org_id_param = sanitize_identifier(params['org_id'])
      end

      def raise_concerns
        require_organization!

        # If explicit org_id provided, validate membership and use that org
        if @org_id_param && !@org_id_param.empty?
          @target_organization = resolve_target_organization(@org_id_param)
          raise_form_error('Organization not found or access denied', field: :org_id, error_type: :unauthorized) unless @target_organization
        else
          @target_organization = organization
        end
      end

      def process
        domains = target_organization.list_domains

        OT.ld "[ListDomains] Processing #{domains.size} domains for org #{target_organization.objid}"

        @custom_domains = domains.map do |domain|
          domain.safe_dump
        end

        success_data
      end

      def success_data
        {
          user_id: @cust.objid,
          organization: target_organization.safe_dump,
          records: @custom_domains,
          count: @custom_domains.length,
          details: {
            cluster: Onetime::Cluster::Features.cluster_safe_dump,
          },
        }
      end

      private

      # Resolve target organization from ID param
      # Returns nil if not found or user is not a member
      #
      # @param org_id [String] Organization ID (objid or extid)
      # @return [Onetime::Organization, nil]
      def resolve_target_organization(org_id)
        # Try loading by objid first, then extid
        # Try loading by objid first, then extid
        # Only rescue expected "not found" errors, let connection/system errors propagate
        org = begin
          Onetime::Organization.load(org_id)
        rescue Familia::NotConnected, Familia::Problem
          raise # Re-raise connection/system errors
        rescue StandardError
          nil # Record not found
        end

        org ||= begin
          Onetime::Organization.find_by_extid(org_id)
        rescue Familia::NotConnected, Familia::Problem
          raise # Re-raise connection/system errors
        rescue StandardError
          nil # Record not found
        end

        return nil unless org
        return nil unless org.member?(@cust)

        org
      end
    end
  end
end
