# lib/onetime/initializers/set_global_secret.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    module SetGlobalSecret

      using IndifferentHashAccess

      def self.run(options = {})
        # Logic from the original Onetime.set_global_secret method
        # Access configuration via OT.conf
        # Example:
        if OT.conf[:site].nil? || OT.conf[:site][:secret].nil?
          raise OT::Problem, "Primary secret is not configured (site.secret)"
        end
        OT.global_secret = OT.conf[:site][:secret]
        OT.ld "[initializer] Global secret set"
      end

    end
  end
end

# module Onetime
#   module Initializers
#     attr_reader :global_secret
#
#     using IndifferentHashAccess
#
#     def set_global_secret
#       @global_secret = OT.conf[:site][:secret] || nil
#       unless Gibbler.secret && Gibbler.secret.frozen?
#         Gibbler.secret = global_secret.freeze
#       end
#     end
#   end
# end
