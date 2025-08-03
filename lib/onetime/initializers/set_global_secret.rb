# lib/onetime/initializers/set_global_secret.rb

module Onetime
  module Initializers
    attr_reader :global_secret

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
  end
end
