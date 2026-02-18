# lib/onetime/initializers/set_secrets.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # SetSecrets initializer
    #
    # Sets the global encryption secret for the application.
    # This secret is used for encrypting/decrypting sensitive data.
    #
    # Runtime state set:
    # - Onetime::Runtime.security.global_secret
    #
    class SetSecrets < Onetime::Boot::Initializer
      @provides = [:secrets]

      def execute(_context)
        global_secret = extract_global_secret

        Onetime::Runtime.security = Onetime::Runtime::Security.new(
          global_secret: global_secret,
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
    end
  end
end
