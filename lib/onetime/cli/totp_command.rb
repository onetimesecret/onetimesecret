# lib/onetime/cli/totp_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # TOTP command placeholder
    # This command is referenced in lib/onetime/cli.rb but was not implemented
    # in the original drydock CLI structure. This is a stub for future implementation.
    class TotpCommand < Command
      desc 'TOTP management (not yet implemented)'

      def call(**)
        boot_application!

        puts 'TOTP command is not yet implemented.'
        puts 'This is a placeholder for future TOTP functionality.'
      end
    end

    register 'totp', TotpCommand
  end
end
