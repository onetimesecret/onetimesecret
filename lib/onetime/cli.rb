# lib/onetime/cli.rb

require 'drydock'
require 'onetime'
require 'onetime/models'
require 'onetime/migration'

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

  class CLI::DelayBoot < Drydock::Command
  end
end

# Load CLI commands
require_relative 'cli/migrate_command'
require_relative 'cli/change_email_command'
require_relative 'cli/migrate_redis_data_command'
require_relative 'cli/customers_command'
require_relative 'cli/domains_command'
require_relative 'cli/session_command'
require_relative 'cli/server_command'

require_relative 'cli/initializers_command'
require_relative 'cli/validate_command'
require_relative 'cli/config_command'
