# apps/web/auth/migrator.rb
# Auto-migration module for Rodauth authentication database
#
# This module provides automatic database migration capabilities
# for the auth service when running in advanced mode. It checks
# if migrations are needed and runs them transparently during
# application startup.

require 'sequel'
require 'logger'

require 'onetime/logger_methods'
require_relative 'database'

module Auth
  module Migrator
    extend Onetime::LoggerMethods

    class << self
      # Run migrations if needed (called during warmup in advanced mode)
      # Sequel::Migrator.run automatically skips already-run migrations
      def run_if_needed
        return unless database_connection

        Sequel.extension :migration

        # Context for all log messages in this operation
        log_context = {
          migrations_dir: OT::Utils.pretty_path(migrations_dir).to_s,
          db_adapter: database_connection.adapter_scheme,
          rack_env: Onetime.env,
        }

        # Don't error if migrations directory doesn't exist or is empty
        unless Dir.exist?(migrations_dir)
          sequel_logger.debug 'Migrations directory not found',
            **log_context,
            action: 'skip',
            reason: 'directory_missing'
          return
        end

        migration_files = Dir.glob(File.join(migrations_dir, '*.rb'))
        if migration_files.empty?
          sequel_logger.debug 'No migration files present',
            **log_context,
            action: 'skip',
            reason: 'no_files'
          return
        end

        # Get current schema version before running migrations
        current_version = begin
          database_connection[:schema_info].first&.fetch(:version, 0)
        rescue Sequel::DatabaseError
          0  # Table doesn't exist yet
        end

        sequel_logger.info 'Starting database migration check',
          **log_context,
          migration_files_count: migration_files.count,
          current_schema_version: current_version

        start_time = Onetime.now_in_μs

        Onetime.auth_logger.debug 'Database migrations starting'
        run_migrations
        Onetime.auth_logger.debug 'Database migrations have run'

        elapsed_μs = Onetime.now_in_μs - start_time

        # Get new schema version
        new_version        = database_connection[:schema_info].first&.fetch(:version, 0)
        migrations_applied = new_version - current_version

        if migrations_applied > 0
          sequel_logger.info 'Database migrations completed',
            **log_context,
            status: 'success',
            migrations_applied: migrations_applied,
            schema_version_before: current_version,
            schema_version_after: new_version,
            elapsed_μs: elapsed_μs
        else
          sequel_logger.info 'Database schema already current',
            **log_context,
            status: 'success',
            migrations_applied: 0,
            schema_version: current_version,
            elapsed_μs: elapsed_μs
        end
      rescue Sequel::Migrator::Error => ex
        elapsed_μs = Onetime.now_in_μs - start_time if start_time

        sequel_logger.error 'Database migration failed',
          **log_context,
          status: 'error',
          error_class: ex.class.name,
          error_message: ex.message,
          error_backtrace: ex.backtrace&.first(5),  # First 5 lines only
          schema_version: current_version,
          elapsed_μs: elapsed_μs

        # Re-raise to prevent app startup with broken schema
        raise
      end

    # Force run all migrations (useful for manual execution)
    def run!
      return unless database_connection

      Sequel.extension :migration

      sequel_logger.info 'Running auth database migrations...'
      run_migrations
      sequel_logger.info 'Auth database migrations completed'
    end

      private

      def database_connection
        @database_connection ||= Auth::Database.connection
      end

      def migrations_dir
        File.join(__dir__, 'migrations')
      end

      def run_migrations
        Sequel.extension :migration

        # Suppress confusing "no such table" errors during migration checks
        # Sequel's create_table? checks existence by attempting a SELECT,
        # which logs an error before being caught. This is expected behavior.
        suppress_table_check_errors do
          Sequel::Migrator.run(
            database_connection,
            migrations_dir,
            use_transactions: true,
          )
        end
      end

      # Temporarily suppress Sequel's logger to prevent confusing error logs
      # during table existence checks in migrations
      def suppress_table_check_errors
        original_loggers = database_connection.loggers.dup
        database_connection.loggers.clear
        yield
      ensure
        database_connection.loggers.clear
        original_loggers.each { |logger| database_connection.loggers << logger }
      end
    end
  end
end
