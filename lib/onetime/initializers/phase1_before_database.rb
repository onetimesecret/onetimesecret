# lib/onetime/initializers/phase1_before_database.rb

module Onetime
  module Initializers
    attr_reader :global_secret, :rotated_secrets

    def run_phase1_initializers
      OT.ld 'Phase 1 Initializers'
      load_locales        # OT.conf[:locales] -> OT.locales
      set_global_secret   # OT.conf[:site][:secret] -> OT.global_secret
      set_rotated_secrets # OT.conf[:site][:rotated_secrets] -> OT.rotated_secrets
      load_fortunes       # OT.conf[:fortunes] ->
    end

    def set_rotated_secrets
      # Remove nil elements that have inadvertently been set in
      # the list of previously used global secrets. Happens easily
      # when using environment vars in the config.yaml that aren't
      # set or are set to an empty string.
      @rotated_secrets = OT.conf[:experimental].fetch(:rotated_secrets, []).compact
    end

    def load_fortunes
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
    end

    def set_global_secret
      @global_secret = OT.conf.dig(:site, :secret) || nil
      unless Gibbler.secret && Gibbler.secret.frozen?
        Gibbler.secret = global_secret.freeze
      end
    end
  end
end
