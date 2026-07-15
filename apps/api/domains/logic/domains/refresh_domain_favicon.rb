# apps/api/domains/logic/domains/refresh_domain_favicon.rb
#
# frozen_string_literal: true

require 'onetime/jobs/publisher'
require_relative '../base'
require_relative '../../policies/domain_config_authorization'

module DomainsAPI::Logic
  module Domains
    # Refresh Domain Favicon
    #
    # @api Enqueues a forced favicon re-fetch for a custom domain (#3780).
    #
    # Authorization model (via DomainConfigAuthorization), same write-path
    # shape as RemoveDomainImage:
    #   1. Load CustomDomain by extid
    #   2. Load Organization via domain.org_id
    #   3. Verify user has manage_org in the organization
    #   4. Verify organization has custom_branding entitlement
    #
    # The enqueue passes force: true so the fetch re-probes even when an
    # auto_fetch icon already exists. The overwrite guard in
    # FetchDomainFavicon still protects a user_upload (or legacy untagged)
    # icon, so a manual refresh cannot clobber a customer-uploaded icon.
    #
    class RefreshDomainFavicon < DomainsAPI::Logic::Base
      include DomainsAPI::Policies::DomainConfigAuthorization

      attr_reader :greenlighted, :custom_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        OT.ld "[#{self.class}] Raising concerns for extid: #{@extid}"

        raise_form_error 'Domain ID is required' if @extid.empty?
        raise_form_error 'Invalid domain identifier format' unless @extid.match?(/\A[a-z0-9]+\z/)

        authorize_domain_config!(@extid)

        @greenlighted = true
      end

      def process
        @queued = false

        # Flag-gate on jobs.favicon_fetch.enabled, mirroring verify_domain.rb.
        # When jobs are disabled the Publisher runs an inline synchronous
        # DNS+HTTPS fetch on the request thread; the gate keeps the manual
        # button consistent with the auto path (dead when the worker is off).
        if OT.conf.dig('jobs', 'favicon_fetch', 'enabled') == true
          begin
            Onetime::Jobs::Publisher.enqueue_favicon_fetch(@custom_domain.identifier, force: true)
            @queued = true
          rescue StandardError => ex
            # The Publisher's jobs-disabled branch runs FetchDomainFavicon inline
            # and can raise FetchTimeout/StandardError; a broker outage can raise
            # on the publish path too. add_domain/verify_domain isolate the same
            # enqueue — do the same here so clicking "Refresh favicon" degrades to
            # a not-queued response instead of a 500.
            OT.le "[#{self.class}] Favicon enqueue failed for #{@custom_domain.display_domain}: #{ex.class} #{ex.message}"
          end
        end

        success_data
      end

      def success_data
        if @queued
          OT.ld "[#{self.class}] Favicon refresh queued for #{@custom_domain.display_domain}"
          msg = "Favicon refresh queued for #{@custom_domain.display_domain}"
        else
          # Feature flag off, or the enqueue failed: don't claim it was queued.
          OT.ld "[#{self.class}] Favicon refresh unavailable for #{@custom_domain.display_domain}"
          msg = 'Favicon refresh is unavailable right now'
        end

        {
          record: nil,
          details: { msg: msg },
        }
      end

      protected

      def config_entitlement
        'custom_branding'
      end

      def config_entitlement_error
        'Custom branding requires the custom_branding entitlement. Please upgrade your plan.'
      end
    end
  end
end
