# lib/onetime/cli_v2.rb
#
# frozen_string_literal: true

require 'dry/cli'
require 'onetime'
require 'onetime/models'
require 'onetime/migration'

require 'v2/logic'

module Onetime
  module CLI
    module V2
      extend Dry::CLI::Registry

      # Base command class that boots the application
      class Command < Dry::CLI::Command
        def initialize
          super
          # Make sure all the models are loaded before calling boot
          OT.boot! :cli
        end

        protected

        def require_sudo
          return if Process.uid.zero?

          raise 'Must run as root or with sudo'
        end

        # Helper to access verbose flag from global options
        def verbose?
          @verbose ||= false
        end

        def debug?
          OT.debug?
        end
      end

      # Command class that delays boot
      class DelayBootCommand < Dry::CLI::Command
        protected

        def require_sudo
          return if Process.uid.zero?

          raise 'Must run as root or with sudo'
        end

        def verbose?
          @verbose ||= false
        end

        def debug?
          OT.debug?
        end
      end
    end
  end
end

# Load CLI commands
require_relative 'cli_v2/load_path_command'
require_relative 'cli_v2/console_command'
require_relative 'cli_v2/server_command'
require_relative 'cli_v2/boot_test_command'
require_relative 'cli_v2/version_command'
require_relative 'cli_v2/help_command'
require_relative 'cli_v2/migrate_command'
require_relative 'cli_v2/migrate_redis_data_command'
require_relative 'cli_v2/sync_auth_accounts_command'
require_relative 'cli_v2/customers_command'
require_relative 'cli_v2/test_data_command'
require_relative 'cli_v2/domains_command'
require_relative 'cli_v2/change_email_command'
require_relative 'cli_v2/revalidate_domains_command'
require_relative 'cli_v2/session_command'
require_relative 'cli_v2/totp_command'
