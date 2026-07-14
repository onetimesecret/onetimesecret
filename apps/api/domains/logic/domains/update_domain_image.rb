# apps/api/domains/logic/domains/update_domain_image.rb
#
# frozen_string_literal: true

require 'base64'
require 'fastimage'

require 'onetime/domain_validation/strategy'
require_relative '../base'
require_relative '../../policies/domain_config_authorization'

module DomainsAPI::Logic
  module Domains
    unless defined?(IMAGE_MIME_TYPES)
      IMAGE_MIME_TYPES = %w[
        image/jpeg image/png image/gif image/svg+xml image/webp image/bmp image/tiff
      ]
      MAX_IMAGE_BYTES  = 2 * 1024 * 1024 # 1 MB
    end

    # Update Domain Image
    #
    # @api Uploads and stores an image (logo or icon) for a custom domain.
    #   Accepts standard image formats (JPEG, PNG, GIF, SVG, WebP, BMP,
    #   TIFF) up to 2 MB. Returns the stored image metadata including
    #   dimensions and ratio.
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
    class UpdateDomainImage < DomainsAPI::Logic::Base
      include DomainsAPI::Policies::DomainConfigAuthorization

      SCHEMAS = { response: 'imageProps' }.freeze

      attr_reader :greenlighted,
        :image,
        :display_domain,
        :custom_domain,
        :content_type,
        :filename,
        :height,
        :width,
        :ratio,
        :bytes

      @field = nil

      class << self
        attr_reader :field

        # Accepted upload MIME types for this image field. Subclasses override to
        # widen the allowlist (e.g. icons also accept .ico). Defaults to the
        # shared IMAGE_MIME_TYPES so logo uploads are unchanged.
        def accepted_mime_types
          IMAGE_MIME_TYPES
        end

        # Maximum upload size in bytes for this image field. Subclasses override
        # to tighten it (e.g. favicons are tiny). Defaults to MAX_IMAGE_BYTES.
        def max_image_bytes
          MAX_IMAGE_BYTES
        end
      end

      def process_params
        @extid = sanitize_identifier(params['extid'])

        OT.ld "[UpdateDomainImage] params keys: #{params.keys.inspect}"
        OT.ld "[UpdateDomainImage] params['image'] class: #{params['image'].class}"
        OT.ld "[UpdateDomainImage] params['image']: #{params['image'].inspect.slice(0, 200)}"

        # Rack 3's multipart parser returns symbol keys (:tempfile, :filename, :type)
        # Stringify them to maintain consistent string keys at API boundaries
        @image = params['image']
        @image = @image.transform_keys(&:to_s) if @image.is_a?(Hash)

        if @image.is_a?(Hash) && @image['tempfile']
          @uploaded_file = @image['tempfile']
          @filename      = @image['filename']
          @content_type  = @image['type']
        elsif @image.respond_to?(:read)
          @uploaded_file = @image
          @filename      = @image.original_filename if @image.respond_to?(:original_filename)
          @content_type  = @image.content_type if @image.respond_to?(:content_type)
        end
      end

      def raise_concerns
        raise_form_error 'Domain ID is required' if @extid.empty?
        raise_form_error 'Invalid domain identifier format' unless @extid.match?(/\A[a-z0-9]+\z/)

        authorize_domain_config!(@extid)

        @display_domain = @custom_domain.display_domain

        raise_form_error 'Image file is required' unless @uploaded_file

        @bytes = @uploaded_file.size
        raise_form_error 'Image file is too large' if bytes > self.class.max_image_bytes
        raise_form_error 'Invalid file type' unless self.class.accepted_mime_types.include?(@content_type)

        @greenlighted = true
      end

      def process
        # Read the file content and encode to Base64
        file_content    = @uploaded_file.read
        encoded_content = Base64.strict_encode64(file_content)

        # Create data URI for FastImage
        data_uri = "data:#{content_type};base64,#{encoded_content}"

        # FastImage.size returns nil for formats it can't measure (some .ico
        # files among them). Guard the ratio division so an unmeasurable icon
        # stores nil dimensions instead of raising on a nil/zero height.
        dimensions    = FastImage.size(data_uri)
        width, height = dimensions
        ratio         = height && !height.zero? ? width.to_f / height : nil

        # Add the encoded image and metadata to the custom domain
        # image field (e.g. logo, icon, etc). These fields are their
        # own db hash keys and not in the main custom domain
        # object hash. That means these attribtues are being
        # directly saved into the database and we do not need to call
        # custom_domain.save to persist these changes.
        _image_field['encoded']      = encoded_content
        _image_field['filename']     = @filename
        _image_field['content_type'] = @content_type
        _image_field['height']       = height
        _image_field['width']        = width
        _image_field['ratio']        = ratio
        _image_field['bytes']        = @bytes

        # Tag the source so the favicon fetch worker never clobbers a user
        # upload, and drop the stale derived favicon cache on re-upload so
        # GetFavicon regenerates from the new bytes (#3780).
        _image_field['favicon_source'] = 'user_upload'
        _image_field.remove_field('encoded_favicon')

        success_data
      end

      def success_data
        klass = self.class
        OT.ld "[#{klass}] Preparing #{klass.field} response for: #{@display_domain}"
        {
          record: _image_field.hgetall,
          details: {
            msg: "Image updated successfully for #{@custom_domain.display_domain}",
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

      # e.g. custom_domain.logo
      def _image_field
        custom_domain.send(self.class.field)
      end
    end

    class UpdateDomainLogo < UpdateDomainImage
      @field = :logo
    end

    class UpdateDomainIcon < UpdateDomainImage
      @field = :icon

      # Favicons commonly ship as .ico, which the shared image allowlist omits —
      # a real favicon upload would otherwise be rejected as "Invalid file type".
      # Widen the allowlist for icons only (logo uploads are untouched).
      ICON_MIME_TYPES = (IMAGE_MIME_TYPES + %w[image/x-icon image/vnd.microsoft.icon]).freeze

      # Favicons are tiny; cap far below the 2 MB shared image limit. Sits above
      # the client-side FAVICON_MAX_BYTES (256 KB in BrandFaviconField) so the
      # client stays the stricter early filter and this is the real server gate.
      MAX_ICON_BYTES = 512 * 1024 # 512 KB

      class << self
        def accepted_mime_types
          ICON_MIME_TYPES
        end

        def max_image_bytes
          MAX_ICON_BYTES
        end
      end
    end
  end
end
