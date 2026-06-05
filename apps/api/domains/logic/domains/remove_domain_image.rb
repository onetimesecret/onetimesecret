# apps/api/domains/logic/domains/remove_domain_image.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require_relative '../base'
require_relative '../../policies/domain_config_authorization'

module DomainsAPI::Logic
  module Domains
    # Remove Domain Image
    #
    # @api Removes a stored image (logo or icon) from a custom domain.
    #
    # Authorization model (via DomainConfigAuthorization):
    #   1. Load CustomDomain by extid
    #   2. Load Organization via domain.org_id
    #   3. Verify user has manage_org in the organization
    #   4. Verify organization has custom_branding entitlement
    #
    # Read-only counterpart GetDomainImage skips manage_org so regular
    # members can view the brand page (disabled overlay in the UI).
    #
    class RemoveDomainImage < DomainsAPI::Logic::Base
      include DomainsAPI::Policies::DomainConfigAuthorization

      attr_reader :greenlighted, :display_domain, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        OT.ld "[#{self.class}] Raising concerns for extid: #{@extid}"

        raise_form_error 'Domain ID is required' if @extid.empty?
        raise_form_error 'Invalid domain identifier format' unless @extid.match?(/\A[a-z0-9]+\z/)

        authorize_domain_config!(@extid)

        @display_domain = @custom_domain.display_domain

        raise_form_error 'No image exists for this domain' unless image_exists?

        @greenlighted = true
      end

      def process
        _image_field.delete! # delete the entire db hash key
        @custom_domain.updated = OT.now.to_i
        @custom_domain.save

        success_data
      end

      def success_data
        OT.ld "[#{self.class}] Preparing success data for display_domain: #{display_domain}"
        {
          record: nil,
          details: {
            msg: "Image removed successfully for #{@custom_domain.display_domain}",
          },
        }
      end

      protected

      def config_entitlement
        'custom_branding'
      end

      def config_entitlement_error
        'Custom branding requires the custom_branding entitlement. Please upgrade your plan.'
      end

      private

      def image_exists?
        _image_field.key?('encoded')
      end

      # e.g. custom_domain.logo
      def _image_field
        custom_domain.send(self.class.field)
      end
    end

    class RemoveDomainLogo < RemoveDomainImage
      @field = :logo
    end

    class RemoveDomainIcon < RemoveDomainImage
      @field = :icon
    end
  end
end
