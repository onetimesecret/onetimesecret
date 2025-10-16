# apps/web/auth/migrator.rb
# Auto-migration module for Rodauth authentication database
#
# This module provides automatic database migration capabilities
# for the auth service when running in advanced mode. It checks
# if migrations are needed and runs them transparently during
# application startup.

require 'sequel'
require 'logger'

module Auth
  module Migrator
    class << self
      # Run migrations if needed (called during warmup in advanced mode)
      def run_if_needed
        return unless database_connection

        begin
          # Check if migrations are needed
          if needs_migration?
            OT.info 'Running auth database migrations...'
            run_migrations
            OT.info 'Auth database migrations completed'
          else
            OT.ld 'Auth database schema is up to date'
          end
        rescue StandardError => ex
          OT.le "Auth migration error: #{ex.message}"
          raise
        end
      end

      # Force run all migrations (useful for manual execution)
      def run!
        return unless database_connection

        OT.info 'Force running auth database migrations...'
        run_migrations
        OT.info 'Auth database migrations completed'
      end

      private

      def database_connection
        @database_connection ||= Auth::Config::Database.connection
      end

      def migrations_dir
        File.join(__dir__, 'migrations')
      end

      def needs_migration?
        # If schema_migrations table doesn't exist, we need migrations
        return true unless database_connection.table_exists?(:schema_migrations)

        # Check if there are pending migrations
        current_version      = database_connection[:schema_migrations].max(:filename)
        available_migrations = Dir[File.join(migrations_dir, '*.rb')].map { |f| File.basename(f) }

        # If no migrations have been run or there are new migrations
        current_version.nil? || available_migrations.any? { |m| m > current_version.to_s }
      end

      def run_migrations
        Sequel.extension :migration
        Sequel::Migrator.run(
          database_connection,
          migrations_dir,
          use_transactions: true,
        )
      end
    end
  end
end
