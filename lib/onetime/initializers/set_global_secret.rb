# lib/onetime/initializers/set_global_secret.rb

module Onetime
  module Initializers
    attr_reader :global_secret

    def set_global_secret
      @global_secret = OT.conf.dig(:site, :secret) || nil
      unless Gibbler.secret && Gibbler.secret.frozen?
        Gibbler.secret = global_secret.freeze
      end
    end
  end
end
