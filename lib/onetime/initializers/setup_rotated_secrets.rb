# lib/onetime/initializers/setup_rotated_secrets.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    module SetupRotatedSecrets

      using IndifferentHashAccess

      def self.run(options = {})
        # Remove nil elements that have inadvertently been set in
        # the list of previously used global secrets. Happens easily
        # when using environment vars in the config.yaml that aren't
        # set or are set to an empty string.
        rotated_secrets = OT.conf[:experimental].fetch(:rotated_secrets, []).compact
        OT.instance_variable_set(:@rotated_secrets, rotated_secrets)
        OT.ld "[initializer] Rotated secrets set (#{rotated_secrets.length} secrets)"
      end

    end
  end
end
