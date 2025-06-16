# lib/onetime/initializers/phase1_before_database.rb

module Onetime
  module Initializers
    attr_reader :global_secret, :rotated_secrets

    def run_phase1_initializers
      OT.ld 'Phase 1 Initializers'
      load_locales        # OT.conf[:locales] -> OT.locales
      set_rotated_secrets # OT.conf[:site][:rotated_secrets] -> OT.rotated_secrets
      set_global_secret   # OT.conf[:site][:secret] -> OT.global_secret
      load_fortunes       # OT.conf[:fortunes] ->
    end

    def load_fortunes
      fortune_path       = File.join(Onetime::HOME, 'src', 'locales', 'en', 'fortunes.json')
      fortunes_list      = OT::Configurator::Load.json_load_file(fortune_path)
      OT::Utils.fortunes = fortunes_list
    end

    def set_global_secret
      @global_secret = OT.conf.dig(:site, :secret) || nil
      unless Gibbler.secret && Gibbler.secret.frozen?
        Gibbler.secret = global_secret.freeze
      end
    end
  end
end
