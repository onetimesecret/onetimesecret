# lib/onetime/initializers/set_secrets.rb

module Onetime
  module Initializers
    attr_reader :global_secret, :rotated_secrets

    def set_secrets
      set_global_secret
      set_rotated_secrets
    end

    private

    def set_global_secret
      @global_secret = OT.conf['site']['secret'] || nil
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

    def set_rotated_secrets
      # Remove nil elements that have inadvertently been set in
      # the list of previously used global secrets. Happens easily
      # when using environment vars in the config.yaml that aren't
      # set or are set to an empty string.
      @rotated_secrets = OT.conf['experimental'].fetch('rotated_secrets', []).compact
    end
  end
end
