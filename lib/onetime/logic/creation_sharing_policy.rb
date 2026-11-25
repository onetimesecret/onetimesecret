# frozen_string_literal: true

require_relative '../secret_sharing_policy'

module Onetime
  module Logic
    module CreationSharingPolicy
      private

      def validate_sharing_controls
        validate_share_domain
        @sharing_policy           = resolve_sharing_policy
        process_ttl(@sharing_policy)
        validate_recipient
        validate_passphrase
        @sharing_controls_checked = true
      end

      def request_sharing_domain
        return unless custom_domain?
        return @request_sharing_domain if defined?(@request_sharing_domain)

        lookup                  = @custom_domain_lookup || Onetime::CustomDomain::Lookup.read(display_domain)
        @request_sharing_domain = lookup.record! || raise_form_error("Unknown domain: #{display_domain}")
      end

      def sharing_domain_record(domain)
        return request_sharing_domain if custom_domain? && domain.casecmp?(display_domain.to_s)

        Onetime::CustomDomain.from_display_domain(domain)
      end

      # Called after validate_share_domain has authorized the selected record.
      # A custom host keeps its owner's policy even if a member selects another
      # authorized domain or an operator link-pool host.
      def resolve_sharing_policy
        host_domain   = request_sharing_domain
        domains       = [host_domain, @selected_sharing_domain].compact.uniq(&:objid)
        workspace     = auth_org unless cust.nil? || cust.anonymous?
        organizations = domains.map do |domain|
          organization = if workspace && workspace.objid == domain.org_id
                           workspace
                         else
                           Onetime::Organization.load(domain.org_id) || raise_form_error('Organization context unavailable')
                         end

          if domain.objid == @selected_sharing_domain&.objid && cust && !cust.anonymous?
            validate_selected_membership(domain, organization)
          end
          @host_organization = organization if domain.objid == host_domain&.objid
          organization
        end
        Onetime::SecretSharingPolicy.new(organizations: [workspace, *organizations], domains: domains)
      end

      def validate_selected_membership(domain, organization)
        membership = Onetime::MembershipSnapshot.for(cust).membership(organization)
        if membership
          return if membership.active? && membership.can_access_domain?(domain)
        elsif domain_strategy.to_s == 'canonical' && organization.member?(cust)
          # CustomDomain#accessible_by? also supports canonical callers whose
          # legacy sorted-set membership predates OrganizationMembership.
          return
        end

        deny_authenticated_domain
      end

      def anonymous_max_ttl(config_max)
        if @host_organization
          return Onetime::SecretLifetimePolicy.organization_guest_ceiling(
            config_max: config_max, organization: @host_organization,
          )
        end

        Onetime::SecretLifetimePolicy.guest_ceiling(
          config_max: config_max, domain_strategy: domain_strategy, display_domain: display_domain,
        )
      end

      def validate_recipient_policy
        policy = @sharing_policy || Onetime::SecretSharingPolicy.new
        # Standard creation sends only the first sanitized address. The caller
        # retains the existing deliverability checks for all submitted addresses.
        return if policy.recipient_allowed?(recipient.first)

        raise_form_error 'Recipient email is restricted by the organization',
          field: 'recipient',
          error_key: 'api.secrets.errors.recipient_policy'
      end
    end
  end
end
