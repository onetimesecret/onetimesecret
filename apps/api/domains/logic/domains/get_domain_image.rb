# apps/api/domains/logic/domains/get_domain_image.rb
#
# frozen_string_literal: true

require 'base64'
require 'onetime/image_content'
require_relative '../../policies/domain_config_authorization'

module DomainsAPI::Logic
  module Domains
    # Get Domain Image
    #
    # @api Retrieves a stored image (logo or icon) for a custom domain as
    #   base64-encoded data with content type metadata. Returns 404 if no
    #   image is stored.
    #
    # Authorization model (read-only, via DomainConfigAuthorization helpers):
    #   1. Load CustomDomain by extid
    #   2. Load Organization via domain.org_id
    #   3. Verify user's membership has custom_branding entitlement
    #
    # Unlike the write counterparts (UpdateDomainImage, RemoveDomainImage),
    # this endpoint does NOT require manage_org. Regular org members can
    # read image data so the UI can render the brand page as a disabled
    # overlay, keeping premium features visible per modern SaaS convention.
    #
    class GetDomainImage < DomainsAPI::Logic::Base
      include DomainsAPI::Policies::DomainConfigAuthorization

      SCHEMAS = { response: 'imageProps' }.freeze

      attr_reader :display_domain, :image_field, :image, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        raise_form_error 'Please provide a domain ID' if @extid.empty?
        raise_form_error 'Invalid domain identifier format' unless @extid.match?(/\A[a-z0-9]+\z/)

        @custom_domain = load_custom_domain(@extid)
        @organization  = load_organization_for_domain(@custom_domain)
        require_entitlement_in!(@organization, config_entitlement)

        # Domain-scope enforcement (#3384)
        membership = Onetime::OrganizationMembership.find_by_org_customer(@organization.objid, @cust.objid)
        if membership && !membership.can_access_domain?(@custom_domain)
          raise_not_found 'Domain not found'
        end

        @display_domain = @custom_domain.display_domain

        @image = _image_field
        raise_not_found 'Image not found' unless image && image['encoded']
      end

      def process
        OT.ld "[#{self.class}] Logo for #{custom_domain.display_domain}"

        # Same gate as the public GetImage: a stored SVG or unknown format is
        # never served there, so the editor shows it as absent too instead of
        # displaying a logo recipients never see.
        @content_type = detected_content_type
        raise_not_found 'Image not found' unless @content_type

        success_data
      end

      def success_data
        {
          record: image.hgetall.merge('content_type' => @content_type), # encoded filename content_type
          details: {},
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

      def detected_content_type
        Onetime::ImageContent.content_type(Base64.strict_decode64(image['encoded']))
      rescue ArgumentError
        nil
      end

      # e.g. custom_domain.logo
      def _image_field
        custom_domain.send(self.class.field)
      end
    end

    class GetDomainLogo < GetDomainImage
      @field = :logo
    end

    class GetDomainIcon < GetDomainImage
      @field = :icon
    end
  end
end
