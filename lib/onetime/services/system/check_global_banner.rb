# lib/onetime/services/system/check_global_banner.rb

module Onetime
  module Services
    module System

      class CheckGlobalBanner < ServiceProvider
        def set_global_secret
          @global_secret = OT.conf.dig(:site, :secret) || nil
          unless Gibbler.secret && Gibbler.secret.frozen?
            Gibbler.secret = global_secret.freeze
          end
        end
      end

    end
  end
end
