# lib/onetime/initializers/check_emailer_config.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # CheckEmailerConfig initializer
    #
    # Builds the mail delivery backend once at boot, so a configuration it
    # cannot be built from (no SMTP host, missing provider credentials, an
    # unsupported setting) is logged on deploy instead of on the first send.
    # The backend is not kept; Mailer builds its own on first use.
    #
    # It never raises. A broken mail configuration stops only mail, so it
    # does not stop boot: the site still serves secrets, and EmailWorker
    # keeps queued messages on the queue until a worker starts with a
    # working configuration (EmailWorker#hold_misconfigured).
    class CheckEmailerConfig < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @optional   = true

      def execute(_context)
        require 'onetime/mail'

        provider = Onetime::Mail::Mailer.validate_delivery_config!
        OT.boot_logger.debug 'Mail delivery configuration checked', provider: provider
      rescue Onetime::Mail::ConfigurationError => ex
        OT.boot_logger.error 'Mail configuration error, email cannot be sent',
          provider: ex.provider,
          error: ex.message
      end
    end
  end
end
