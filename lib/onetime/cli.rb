# lib/onetime/cli.rb
#
# frozen_string_literal: true

require 'dry/cli'
require 'onetime'
require 'onetime/models'
require 'onetime/migration'

require 'v2/logic'

module Onetime
  module CLI
    extend Dry::CLI::Registry

    # Base command class that boots the application
    class Command < Dry::CLI::Command
      def boot_application!
        # Make sure all the models are loaded before calling boot
        OT.boot! :cli

        # boot! swallows exceptions in CLI mode (for console debugging).
        # Commands that depend on a fully-booted app should fail fast
        # with a clear message instead of hitting nil errors later.
        warn 'Boot failed: OT.conf is nil' unless OT.conf
      end

      protected

      def require_sudo
        return if Process.uid.zero?

        raise 'Must run as root or with sudo'
      end

      def verbose?
        ARGV.any? { |arg| ['-v', '--verbose'].include?(arg) }
      end

      def debug?
        OT.debug?
      end
    end

    # Command class that delays boot (for commands that handle boot themselves)
    class DelayBootCommand < Dry::CLI::Command
      protected

      def require_sudo
        return if Process.uid.zero?

        raise 'Must run as root or with sudo'
      end

      def verbose?
        ARGV.any? { |arg| ['-v', '--verbose'].include?(arg) }
      end

      def debug?
        OT.debug?
      end
    end
  end
end

# Load core CLI commands
require_relative 'cli/simple_commands'
require_relative 'cli/status_command'
require_relative 'cli/server_command'
require_relative 'cli/boot_test_command'
require_relative 'cli/migrate_command'
require_relative 'cli/migrate_redis_data_command'
require_relative 'cli/customers/sync_auth_accounts_command'
require_relative 'cli/customers_command'

# Load migration CLI commands
require_relative 'cli/migrations/backfill_email_hash_command'
require_relative 'cli/migrations/backfill_stripe_email_hash_command'
require_relative 'cli/migrations/backfill_subscription_status_command'
require_relative 'cli/migrations/dedupe_instances_command'
require_relative 'cli/migrations/dedupe_relationships_command'
require_relative 'cli/migrations/dedupe_participations_command'
require_relative 'cli/passwords_command'
require_relative 'cli/test_data_command'
require_relative 'cli/change_email_command'
require_relative 'cli/session_command'
require_relative 'cli/totp_command'

# Load worker and scheduler commands (top-level)
require_relative 'cli/worker_command'
require_relative 'cli/scheduler_command'

# Load email CLI commands
require_relative 'cli/email'
require_relative 'cli/email/send_command'
require_relative 'cli/email/test_command'
require_relative 'cli/email/templates_command'
require_relative 'cli/email/preview_command'
require_relative 'cli/email/config_command'

# Load install CLI commands
require_relative 'cli/install_command'

# Load queue CLI commands
require_relative 'cli/queue/init_command'
require_relative 'cli/queue/status_command'
require_relative 'cli/queue/reset_command'
require_relative 'cli/queue/dlq_command'
require_relative 'cli/queue/ping_command'

# Auto-discover app CLI commands
apps_root = File.join(ENV['ONETIME_HOME'] || Dir.pwd, 'apps')
if Dir.exist?(apps_root)
  cli_patterns = [
    File.join(apps_root, '*', 'cli', '**', '*_command.rb'),
    File.join(apps_root, '*', '*', 'cli', '**', '*_command.rb'),
  ]

  cli_patterns.each do |pattern|
    Dir.glob(pattern).each do |file|
      require file
    end
  end
end
