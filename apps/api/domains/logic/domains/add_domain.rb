# apps/api/domains/logic/domains/add_domain.rb
#
# frozen_string_literal: true

require 'public_suffix'

require 'onetime/domain_validation/features'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    # Add Custom Domain
    #
    # @api Registers a new custom domain for an organization. Validates
    #   the domain via PublicSuffix and checks for duplicates. Returns the
    #   created domain record. When the new domain is served right away, it
    #   also becomes the active domain context in the session.
    #
    # No certificate is requested here. Under a strategy that manages
    # certificates (approximated) the virtual host is created by
    # verification once ownership is verified (Operations::VerifyDomain),
    # so a name whose owner never proves it gets no certificate.
    #
    # Supports two modes:
    # 1. Default: Uses organization from session context
    # 2. Explicit: Uses org_id param (must be an org the user is a member of)
    #
    # The explicit mode allows the frontend to add domains to a specific
    # organization when the user switches organizations in the UI, before
    # the session is updated.
    #
    class AddDomain < DomainsAPI::Logic::Base
      include Onetime::LoggerMethods

      SCHEMAS = { response: 'customDomain' }.freeze

      attr_reader :greenlighted, :custom_domain, :domain_input, :display_domain, :target_organization

      def process_params
        # Sanitize plain text to strip HTML tags before PublicSuffix normalizes
        @domain_input = sanitize_plain_text(params['domain'])
        @org_id_param = sanitize_identifier(params['org_id'])

        logger.debug '[AddDomain] Parsing domain', domain_input: domain_input
      end

      def raise_concerns
        logger.debug '[AddDomain] Raising any concerns about domain', domain_input: @domain_input
        # TODO: Consider returning all applicable errors (plural) at once
        raise_form_error 'Please enter a domain' if @domain_input.empty?
        raise_form_error 'Not a valid public domain' unless Onetime::CustomDomain.valid?(@domain_input)
        raise_form_error 'This domain overlaps with the default site domain' if Onetime::CustomDomain.overlaps_canonical_domain?(@domain_input)

        # Require organization for domain ownership
        require_organization!

        # If explicit org_id provided, validate membership and use that org
        if @org_id_param && !@org_id_param.empty?
          @target_organization = resolve_target_organization(@org_id_param)
          raise_form_error('Organization not found or access denied', field: :org_id, error_type: :unauthorized) unless @target_organization
        else
          @target_organization = organization
        end

        # Authorization: only users with custom_domains entitlement in the target
        # organization may add a custom domain. Colonels bypass via require_entitlement_in!.
        require_entitlement_in!(@target_organization, 'custom_domains')

        # Custom domains are now available to all plans (free included)
        # Entitlement check removed - this feature is universally available

        # Only store a valid, parsed input value to @domain. parse refuses
        # some names valid? accepts (too deep, TXT challenge name too long)
        # with a message meant for the customer.
        @parsed_domain  = refuse_on_problem { Onetime::CustomDomain.parse(@domain_input, target_organization.objid) }
        @display_domain = @parsed_domain.display_domain

        logger.debug '[AddDomain] Domain parsed', display_domain: @display_domain, identifier: @parsed_domain.identifier

        # Check for existing domain to provide specific error messages
        existing = Onetime::CustomDomain.load_by_display_domain(@display_domain)

        return unless existing

        # Scenario 1: Domain already in customer's organization (same org_id)
        if existing.org_id.to_s == target_organization.objid.to_s
          logger.debug '[AddDomain] Domain already in organization', display_domain: @display_domain
          raise_form_error 'Domain already registered in your organization'
        end

        # Scenario 2: Domain in another organization (different org_id)
        unless existing.org_id.to_s.empty?
          logger.error '[AddDomain] Domain belongs to another organization', display_domain: @display_domain
          raise_form_error 'Domain is registered to another organization'
        end

        # Scenario 3: Orphaned domain (no org_id). Only an operator adopts
        # an orphan; this answers like Scenario 2 and logs the refusal, before
        # anything is written or a certificate is requested.
        refuse_on_problem { Onetime::CustomDomain.refuse_orphan_claim!(existing, target_organization.objid) }
      end

      def process
        @greenlighted  = true
        logger.debug '[AddDomain] Processing domain', display_domain: @display_domain, org_id: target_organization.objid

        @custom_domain = refuse_on_problem { Onetime::CustomDomain.create!(@display_domain, target_organization.objid) }

        # Make the new domain the active context in the session, but only
        # when it is served (CustomDomain#served_as_tenant?). Under a strategy
        # that checks ownership it is not served until verified, and the
        # context is the share_domain of the next secret, which secret
        # creation refuses for an unserved domain. Route is sessionauth-only,
        # so sess is always a real Rack session here.
        sess['domain_context'] = domain_context if domain_context

        # Auto-fetch the domain's favicon on add (#3780). Flag-gated and isolated:
        # the Publisher's jobs-disabled branch runs FetchDomainFavicon inline and can
        # raise, so wrap it so a favicon failure never breaks domain creation.
        if OT.conf.dig('jobs', 'favicon_fetch', 'enabled') == true
          begin
            Onetime::Jobs::Publisher.enqueue_favicon_fetch(@custom_domain.identifier)
          rescue StandardError => ex
            logger.error '[AddDomain] Failed to enqueue favicon fetch', display_domain: @display_domain, exception: ex
          end
        end

        success_data
      end

      # The model refuses a domain with a bare Onetime::Problem whose message
      # is written for the customer. No handler is registered for the bare
      # class, so it would surface as a 500; it becomes a form error (422)
      # instead. Subclasses keep their own handlers.
      def refuse_on_problem
        yield
      rescue Onetime::Problem => ex
        raise unless ex.instance_of?(Onetime::Problem)

        raise_form_error ex.message
      end

      # domain_context is the context #process set in the session, nil when
      # it set none. It is in details too, where the client reads it
      # (customDomainDetailsSchema).
      def success_data
        {
          user_id: @cust.objid,
          organization: target_organization.safe_dump,
          record: @custom_domain.safe_dump,
          domain_context: domain_context,
          details: {
            cluster: Onetime::DomainValidation::Features.safe_dump,
            domain_context: domain_context,
          },
        }
      end

      # The new domain's name when it is served
      # (CustomDomain#served_as_tenant?), else nil. #process sets it as the
      # session's domain context.
      def domain_context
        @display_domain if @custom_domain&.served_as_tenant?
      end
    end
  end
end
