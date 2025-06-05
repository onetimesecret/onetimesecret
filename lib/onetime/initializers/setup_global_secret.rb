# lib/onetime/initializers/setup_global_secret.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    module SetupGlobalSecret

      using IndifferentHashAccess

      def self.run(options = {})
        if OT.conf[:site].nil? || OT.conf[:site][:secret].nil?
          raise OT::Problem, "Primary secret is not configured (site.secret)"
        end
        OT.global_secret = OT.conf[:site][:secret]

        # Set Gibbler secret if not already set
        unless Gibbler.secret && Gibbler.secret.frozen?
          Gibbler.secret = OT.global_secret.freeze
        end

        OT.ld "[initializer] Global secret set"
      end

    end
  end
end
