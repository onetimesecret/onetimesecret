# apps/api/v2/logic/secrets/display_type_param.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    # The conceal request's display_type: read it, put it in canonical form,
    # and refuse a type this build does not know. The request-side
    # counterpart of the Secret's display_type feature
    # (lib/onetime/models/secret/features/display_type.rb), which owns the
    # value space.
    #
    # Contract: absent or blank means plain text. The value is a
    # presentation hint for the recipient's client, stored verbatim on the
    # Secret and echoed in its safe_dump. An unknown type, or a known one
    # this platform has not turned on (features.markdown.enabled), is a 422
    # at creation rather than a surprise at reveal. A type with a rule about the
    # content (an httplink value must be a URL) checks it here, beside
    # validate_display_type, while the plaintext is in hand.
    #
    # Included by BaseSecretAction, whose payload, scalar_param? and
    # raise_form_error it uses. GenerateSecret overrides process_display_type:
    # a generated value is always text.
    module DisplayTypeParam
      attr_reader :display_type

      protected

      def process_display_type
        raw = payload.fetch('display_type', nil)
        # `secret[display_type][]=x` arrives as an Array; `.to_s` would store
        # its inspect form and the check below would reject it with a
        # misleading message. Reject the shape up front like ttl does.
        raise_form_error 'Incorrect payload format', field: :display_type unless scalar_param?(raw)

        @display_type = Onetime::Secret.normalize_display_type(raw)
      end

      # Fail at creation: the creator can correct the request, whereas the
      # recipient could only see a silent fallback to plain text.
      def validate_display_type
        unless Onetime::Secret.valid_display_type?(display_type)
          raise_form_error "Unknown display type: #{display_type}",
            field: :display_type,
            error_type: :invalid
        end
        return if Onetime::Secret.display_type_enabled?(display_type)

        raise_form_error "Display type not enabled: #{display_type}",
          field: :display_type,
          error_type: :invalid
      end
    end
  end
end
