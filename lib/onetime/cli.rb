# lib/onetime/cli.rb

require 'drydock'
require 'onetime'
require 'familia/tools'
require 'onetime/migration'

require 'v2/models'
require 'v2/logic'

module Onetime
  class CLI < Drydock::Command
    def init
      # Make sure all the models are loaded before calling boot
      OT.boot! :cli
    end

    private

    def require_sudo
      return if Process.uid.zero?

      raise 'Must run as root or with sudo'
    end
  end
end

# Load CLI commands
require_relative 'cli/migrate_command'
require_relative 'cli/move_keys_command'
require_relative 'cli/customers_command'
require_relative 'cli/domains_command'
require_relative 'cli/change_email_command'
require_relative 'cli/initializers_command'
require_relative 'cli/validate_command'
require_relative 'cli/config_command'
