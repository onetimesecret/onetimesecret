# lib/onetime/initializers/set_rotated_secrets.rb

module Onetime
  module Initializers
    attr_reader :rotated_secrets

    def set_rotated_secrets

      # Remove nil elements that have inadvertently been set in
      # the list of previously used global secrets. Happens easily
      # when using environment vars in the config.yaml that aren't
      # set or are set to an empty string.
      @rotated_secrets = OT.conf['experimental'].fetch('rotated_secrets', []).compact

    end
  end
end
