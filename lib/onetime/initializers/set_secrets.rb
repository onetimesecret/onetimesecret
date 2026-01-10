# lib/onetime/initializers/set_secrets.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # SetSecrets initializer
    #
    # Sets the global encryption secret and rotated secrets for the application.
    # These secrets are used for encrypting/decrypting sensitive data.
    #
    # Runtime state set:
    # - Onetime::Runtime.security.global_secret
    # - Onetime::Runtime.security.rotated_secrets
    #
    # KNOWN LIMITATION: rotated_secrets only supports LegacyEncryptedFields
    # (Secret/Metadata content encryption). It does NOT integrate with:
    # - Familia's EncryptedFields (configured separately in configure_familia.rb)
    # - SESSION_SECRET or HMAC_SECRET (separate ENV-based systems)
    #
    class SetSecrets < Onetime::Boot::Initializer
      @provides = [:secrets]

      def execute(_context)
        global_secret   = extract_global_secret
        rotated_secrets = extract_rotated_secrets

        Onetime::Runtime.security = Onetime::Runtime::Security.new(
          global_secret: global_secret,
          rotated_secrets: rotated_secrets,
        )

        # NOTE: Setting this value affects the gibbler output (obvs) so anywhere
        # that we relied on identifying values remaining the same based on the
        # same input will be affected by Gibbler.secret not being set anymore.
        # This mainly affects the domainid which is based on the custid/email
        # of the owner and display_domain.
        #
        # unless Gibbler.secret && Gibbler.secret.frozen?
        #   # Gibbler.secret = global_secret.freeze
        # end
      end

      private

      def extract_global_secret
        OT.conf['site']['secret'] || nil
      end

      def extract_rotated_secrets
        # Remove nil elements that have inadvertently been set in
        # the list of previously used global secrets. Happens easily
        # when using environment vars in the config.yaml that aren't
        # set or are set to an empty string.
        OT.conf['experimental'].fetch('rotated_secrets', []).compact
      end
    end
  end
end
