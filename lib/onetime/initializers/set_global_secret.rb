# lib/onetime/initializers/set_global_secret.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    attr_reader :global_secret

    using IndifferentHashAccess

    def set_global_secret
      @global_secret = OT.conf[:site][:secret] || nil
      unless Gibbler.secret && Gibbler.secret.frozen?
        Gibbler.secret = global_secret.freeze
      end
    end
  end
end
