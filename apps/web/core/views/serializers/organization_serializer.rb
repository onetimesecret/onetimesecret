# apps/web/core/views/serializers/organization_serializer.rb
#
# frozen_string_literal: true

require 'onetime/logger_methods'

module Core
  module Views
    # Serializes organization data for the frontend bootstrap payload
    #
    # Provides the current user's organization context to the frontend,
    # enabling domain context initialization without race conditions.
    # The organization is loaded via OrganizationLoader in the auth strategy.
    module OrganizationSerializer
      extend Onetime::LoggerMethods

      # Free-tier limit literals used only when the free_v1 plan itself
      # cannot be resolved from billing config. Values mirror free_v1 in
      # billing.yaml (teams is absent there: free tier has none).
      FALLBACK_FREE_TIER_LIMITS = {
        'teams' => 0,
        'total_members_per_org' => 1,
        'custom_domains' => 1,
      }.freeze

      # Serializes organization data from view variables
      #
      # @param view_vars [Hash] The view variables containing organization info
      # @return [Hash] Serialized organization data
      def self.serialize(view_vars)
        output = output_template

        is_authenticated = view_vars['authenticated']
        org              = view_vars['organization']

        return output unless is_authenticated && org

        # Serialize minimal organization data needed for frontend initialization
        # Full organization details can be fetched via API when needed
        output['organization'] = serialize_organization(org, view_vars['cust'])

        output
      end

      class << self
        # Provides the base template for organization serializer output
        #
        # @return [Hash] Template with organization output fields
        def output_template
          {
            'organization' => nil,
          }
        end

        private

        # Serialize organization to frontend format
        #
        # Includes only the fields needed for:
        # - Domain context initialization (id, extid)
        # - Basic display (display_name, is_default)
        # - Plan identity and role (planid, current_user_role)
        # - Feature gating and quota display (entitlements, limits)
        #
        # entitlements and limit_for resolve through the request-scoped
        # preview context (ADR-020), so this bootstrap payload reflects
        # colonel preview mode without any per-consumer wiring.
        #
        # @param org [Onetime::Organization] Organization to serialize
        # @param cust [Onetime::Customer] Current user for role calculation
        # @return [Hash] Serialized organization data
        def serialize_organization(org, cust)
          entitlements, limits = plan_derived_fields(org)
          {
            'objid' => org.objid,
            'extid' => org.extid,
            'display_name' => org.display_name,
            'is_default' => org.is_default || false,
            'planid' => org.planid,
            'current_user_role' => determine_user_role(org, cust),
            'entitlements' => entitlements,
            'limits' => limits,
          }
        end

        # Resolve entitlements and limits for the bootstrap payload
        #
        # Both readers fail closed (Billing::PlanCacheMissError) when the
        # org's planid resolves from neither the plan cache nor billing.yaml.
        # Degrade to free tier at this read edge only — the model raise must
        # stay so enforcement paths (require_entitlement!) remain fail-closed,
        # but a bootstrap read raising takes login down with a 503.
        #
        # @param org [Onetime::Organization] Organization
        # @return [Array(Array<String>, Hash)] Entitlements and limits
        def plan_derived_fields(org)
          [org.entitlements, serialize_limits(org)]
        rescue StandardError => ex
          # Match by name: builds without the billing app never define (or
          # raise) the error class, and a bare rescue would NameError here.
          raise unless defined?(::Billing::PlanCacheMissError) && ex.is_a?(::Billing::PlanCacheMissError)

          OT.le "[OrganizationSerializer] Plan catalog unavailable, degrading to free tier: plan=#{org.planid} org=#{org.extid}"
          [
            Onetime::Models::Features::WithPlanEntitlements::FREE_TIER_ENTITLEMENTS.dup,
            free_tier_fallback_limits,
          ]
        end

        # Free-tier limits for the degraded bootstrap payload
        #
        # Resolves free_v1 from billing config when possible (config loading
        # rescues internally, so this returns nil rather than raising), with
        # FALLBACK_FREE_TIER_LIMITS literals per missing key. Same shape as
        # serialize_limits: integers, -1 for unlimited.
        #
        # @return [Hash] Normalized limits
        def free_tier_fallback_limits
          config_limits =
            if defined?(::Billing::Plan)
              (::Billing::Plan.load_from_config('free_v1') || {})[:limits] || {}
            else
              {}
            end

          FALLBACK_FREE_TIER_LIMITS.to_h do |key, default|
            val        = config_limits["#{key}.max"]
            normalized =
              if val.nil?
                default
              elsif val == 'unlimited'
                -1
              else
                val.to_i
              end
            [key, normalized]
          end
        end

        # Limits for the bootstrap payload, matching the safe_dump shape
        # (organization/features/safe_dump_fields.rb): Float::INFINITY
        # normalizes to -1 for JSON serialization (unlimited).
        #
        # @param org [Onetime::Organization] Organization
        # @return [Hash] Normalized limits
        def serialize_limits(org)
          normalize = ->(val) { val == Float::INFINITY ? -1 : val.to_i }
          {
            'teams' => normalize.call(org.limit_for(:teams)),
            'total_members_per_org' => normalize.call(org.limit_for(:total_members_per_org)),
            'custom_domains' => normalize.call(org.limit_for(:custom_domains)),
          }
        end

        # Determine the current user's role in the organization
        #
        # @param org [Onetime::Organization] Organization
        # @param cust [Onetime::Customer] Current user
        # @return [String, nil] Role name or nil
        def determine_user_role(org, cust)
          return nil unless cust && !cust.anonymous?

          if org.owner?(cust)
            'owner'
          elsif org.member?(cust)
            membership = Onetime::OrganizationMembership.find_by_org_customer(
              org.objid, cust.objid
            )
            membership&.role || 'member'
          end
        end
      end

      SerializerRegistry.register(self, ['AuthenticationSerializer'])
    end
  end
end
