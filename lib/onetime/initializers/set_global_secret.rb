# lib/onetime/initializers/set_global_secret.rb

module Onetime
  module Initializers
    attr_reader :global_secret, :global_banner

    def set_global_secret
      @global_secret = OT.conf[:site][:secret] || nil
      unless Gibbler.secret && Gibbler.secret.frozen?
        Gibbler.secret = global_secret.freeze
      end
    end

    def load_fortunes
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
    end

    def check_global_banner
      @global_banner = Familia.redis(0).get('global_banner')
      OT.li "Global banner: #{OT.global_banner}" if global_banner
    end

    def load_plans
      OT::Plan.load_plans!
    end

  end
end
