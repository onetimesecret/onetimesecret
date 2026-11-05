# apps/api/domains/logic/domains/remove_domain.rb
#
# frozen_string_literal: true

require 'onetime/operations/domains/teardown'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    class RemoveDomain < DomainsAPI::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :greenlighted, :extid, :display_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        raise_form_error 'Please provide a domain ID' if @extid.empty?

        # Get customer's organization for domain ownership
        # Organization available via @organization
        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)
        raise_form_error 'Domain not found' unless @custom_domain

        # Verify the customer can access this domain through org membership
        unless @custom_domain.accessible_by?(@cust)
          raise_form_error 'Domain not found'
        end

        # Domain deletion requires admin+ (custom_domains entitlement),
        # consistent with AddDomain (#3033) and GetDomain.
        # Damaged ownership metadata answers 'Domain not found', exactly like
        # the membership refusal above, and the nil never reaches
        # require_entitlement_in!.
        domain_org = load_organization_for_domain(@custom_domain) do
          raise_form_error 'Domain not found'
        end
        require_entitlement_in!(domain_org, 'custom_domains')

        # Domain-scope enforcement: deny cross-domain deletion (#3384).
        # nil membership is colonel-only here: require_entitlement_in! above
        # already rejected any non-colonel without an active membership row.
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          domain_org.objid, @cust.objid
        )
        if membership && !membership.can_access_domain?(@custom_domain)
          raise_not_found 'Domain not found'
        end
      end

      def process
        app_logger.debug '[RemoveDomain] Processing', domain_extid: @extid, domain_display: @custom_domain.display_domain
        @greenlighted   = true
        @display_domain = @custom_domain.display_domain

        teardown    = Onetime::Operations::Domains::Teardown.new(domain: @custom_domain).call
        lease_error = teardown.lease_error

        # Clear the session's domain context if it matches the removed domain.
        # Route is sessionauth-only, so sess is always a real Rack session.
        if sess && sess['domain_context'] == @display_domain
          sess['domain_context'] = nil
        end

        # sender_cleanup is the remote sender identity outcome
        # (Teardown::Result#sender_cleanup). It is logged, not returned: the
        # response shape is unchanged, and a failed cleanup does not undo the
        # removal. A failed cleanup logs at warn; DeleteSenderDomain has
        # already logged the provider error.
        removal_log = {
          event: 'domain_removed',
          domain_extid: @extid,
          domain_display: @display_domain,
          actor_extid: cust.extid,
          sender_cleanup: teardown.sender_cleanup.to_s,
        }
        level       = teardown.sender_cleanup == :failed ? :warn : :info

        if lease_error
          details = { removal_committed: true, lease_lost: true }
          app_logger.public_send(level, '[RemoveDomain] Domain removal committed with lease loss', **details, **removal_log)
          raise_form_error(
            "Domain #{@display_domain} was removed, but #{lease_error.message}",
            field: :extid,
            error_type: :conflict,
            details: details,
          )
        end

        app_logger.public_send(level, '[RemoveDomain] Domain removed', **removal_log)
        success_data
      rescue Onetime::Operations::Domains::Teardown::Busy
        raise_form_error("Another change to this domain's sender configuration is in progress. Please try again.", field: :extid, error_type: :conflict)
      rescue Onetime::Operations::SenderIdentityLease::Lost => ex
        raise_form_error(ex.message, field: :extid, error_type: :conflict)
      end

      def success_data
        {
          user_id: @cust.objid,
          record: {},
          message: "Removed #{display_domain}",
        }
      end
    end
  end
end
