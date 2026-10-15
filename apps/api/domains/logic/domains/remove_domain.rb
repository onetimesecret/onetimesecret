# apps/api/domains/logic/domains/remove_domain.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require 'onetime/operations/delete_sender_domain'
require 'onetime/operations/sender_identity_lease'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    class RemoveDomain < DomainsAPI::Logic::Base
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
        OT.ld "[RemoveDomain] Processing #{@extid} (#{@custom_domain.display_domain})"
        @greenlighted   = true
        @display_domain = @custom_domain.display_domain

        # Hold the domain's sender identity lock from the provider teardown
        # through destroy!, and refuse while provisioning holds it. A
        # provision that ran in between would register the identity again
        # after the teardown, and destroy! would then delete the only record
        # of it. Taken before the first teardown step, so a refusal leaves
        # the domain as it was.
        lock       = Onetime::CustomDomain::MailerConfig.sender_identity_lock(@custom_domain.identifier)
        lease      = Onetime::Operations::SenderIdentityLease.new(lock)
        unless lease.acquire
          raise_form_error("Another change to this domain's sender configuration is in progress. Please try again.", field: :extid, error_type: :conflict)
        end

        removal_committed = false
        lease_error       = nil
        begin
          lease.protect do
            # Delete from external SSL provider via strategy
            delete_vhost
            lease.check!

            # Delete from external mail provider before destroy! wipes mailer_config
            delete_sender_domain
            lease.check!

            # Destroy method operates inside a multi block that deletes the domain
            # record, removes it from customer's domain list, and global list so
            # it's all or nothing. It does not delete the external approximated
            # vhost record.
            @custom_domain.destroy!
            removal_committed = true
          end
        rescue Onetime::Operations::SenderIdentityLease::Lost => ex
          raise unless removal_committed

          lease_error = ex
        end

        # Clear the session's domain context if it matches the removed domain.
        # Route is sessionauth-only, so sess is always a real Rack session.
        if sess && sess['domain_context'] == @display_domain
          sess['domain_context'] = nil
        end

        if lease_error
          details = { removal_committed: true, lease_lost: true }
          OT.info '[RemoveDomain] Domain removal committed with lease loss',
            details.merge(
              event: 'domain_removed',
              domain_extid: @extid,
              domain_display: @display_domain,
              actor_extid: cust.extid,
            ).to_json
          raise_form_error(
            "Domain #{@display_domain} was removed, but #{lease_error.message}",
            field: :extid,
            error_type: :conflict,
            details: details,
          )
        end

        success_data
      rescue Onetime::Operations::SenderIdentityLease::Lost => ex
        raise_form_error(ex.message, field: :extid, error_type: :conflict)
      end

      # Deletes vhost from external provider using the configured strategy.
      # For Approximated strategy, this calls the API. For other strategies,
      # this is a no-op.
      #
      def delete_vhost
        strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
        result   = strategy.delete_vhost(@custom_domain)

        OT.info "[RemoveDomain.delete_vhost] #{@display_domain} -> #{result[:message]}"
      rescue HTTParty::ResponseError, Timeout::Error, Errno::ECONNREFUSED => ex
        OT.le "[RemoveDomain.delete_vhost error] #{@cust.extid} #{@display_domain} #{ex}"
        # Continue with domain removal even if vhost deletion fails
      end

      def delete_sender_domain
        Onetime::Operations::DeleteSenderDomain.new(
          mailer_config: @custom_domain.mailer_config,
        ).call
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
