# apps/api/v3/logic/incoming/base_incoming.rb
#
# frozen_string_literal: true

require_relative '../base'

module V3
  module Logic
    module Incoming
      # Base class for incoming secret logic classes.
      #
      # Provides domain-aware entitlement gating: on custom domains,
      # resolves the domain-owning organization and checks for the
      # `incoming_secrets` entitlement. On the canonical domain,
      # defers to the global config flag.
      #
      class BaseIncoming < V3::Logic::Base
        private

        # Resolve the organization that owns the current request domain.
        #
        # For custom domains, looks up the CustomDomain record and returns
        # its primary_organization. For the canonical domain, returns nil.
        #
        # @return [Onetime::Organization, nil]
        def domain_owning_organization
          return @domain_owning_org if defined?(@domain_owning_org)

          @domain_owning_org = if custom_domain? && display_domain
            domain_record = Onetime::CustomDomain.from_display_domain(display_domain)
            domain_record&.primary_organization
          end
        end

        # Check incoming_secrets entitlement against the domain-owning org.
        #
        # On the canonical domain (no custom domain), returns true so the
        # global config flag remains the sole gate (unchanged behavior).
        #
        # On a custom domain, requires the owning org to have the
        # `incoming_secrets` entitlement. Raises EntitlementRequired
        # with upgrade path info if the check fails.
        #
        # @raise [Onetime::EntitlementRequired]
        # @return [true]
        def require_incoming_entitlement!
          owning_org = domain_owning_organization

          # Canonical domain: global config controls access (unchanged)
          return true unless owning_org

          return true if owning_org.can?('incoming_secrets')

          current_plan = owning_org.planid
          upgrade_to = if defined?(Billing::PlanHelpers)
                         Billing::PlanHelpers.upgrade_path_for('incoming_secrets', current_plan)
                       end

          raise Onetime::EntitlementRequired.new(
            'incoming_secrets',
            current_plan: current_plan,
            upgrade_to: upgrade_to,
          )
        end
      end
    end
  end
end
