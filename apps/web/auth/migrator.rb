# apps/web/auth/migrator.rb
#
# frozen_string_literal: true

# Auto-migration module for Rodauth authentication database
#
# This module provides automatic database migration capabilities
# for the auth service when running in full mode. It checks
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
      # Run migrations if needed (called during warmup in full mode)
      # Sequel::Migrator.run automatically skips already-run migrations
      def run_if_needed
        unless database_connection
          sequel_logger.debug 'Skipping migrations - no database connection',
            full_mode_enabled: Onetime.auth_config&.full_enabled?,
            database_url_present: !Onetime.auth_config&.database_url.nil?
          return
        end

        # Determine which connection to use for migrations
        using_elevated_url = Onetime.auth_config.database_url_migrations != Onetime.auth_config.database_url

        sequel_logger.info 'Auth migrations initializer running',
          database_url: Onetime.auth_config.database_url&.sub(/:[^:@]+@/, ':***@'), # Mask password
          migrations_url: Onetime.auth_config.database_url_migrations&.sub(/:[^:@]+@/, ':***@'),
          using_elevated_credentials: using_elevated_url

        Sequel.extension :migration

        # Test connection early using the URL we'll use for migrations
        # This provides clearer error messages if connection fails
        test_conn = using_elevated_url ? migration_connection : database_connection
        adapter_scheme = begin
          test_conn.adapter_scheme
        rescue StandardError => ex
          sequel_logger.error 'Failed to connect to auth database',
            error: ex.message,
            error_class: ex.class.name,
            database_url: using_elevated_url ? Onetime.auth_config.database_url_migrations&.sub(/:[^:@]+@/, ':***@') : Onetime.auth_config.database_url&.sub(/:[^:@]+@/, ':***@'),
            using_elevated_url: using_elevated_url
          raise
        ensure
          # Disconnect test connection if it was the migrations connection
          test_conn.disconnect if using_elevated_url && test_conn != database_connection
        end

        # Context for all log messages in this operation
        log_context = {
          migrations_dir: OT::Utils.pretty_path(migrations_dir).to_s,
          db_adapter: adapter_scheme,
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

      # Create a dedicated connection for migrations using AUTH_DATABASE_URL_MIGRATIONS
      # This allows using a superuser/admin account for schema changes while the
      # application runs with restricted privileges
      def migration_connection
        database_url = Onetime.auth_config.database_url_migrations

        sequel_logger.debug 'Creating migration database connection',
          url_type: database_url == Onetime.auth_config.database_url ? 'standard' : 'elevated'

        Sequel.connect(
          database_url,
          logger: Onetime.get_logger('Sequel'),
          sql_log_level: :trace,
        )
      end

      def run_migrations
        Sequel.extension :migration

        # Use dedicated migration connection if AUTH_DATABASE_URL_MIGRATIONS is set
        # Otherwise fall back to regular database connection
        conn = if Onetime.auth_config.database_url_migrations == Onetime.auth_config.database_url
          database_connection
        else
          migration_connection
        end

        begin
          # Suppress confusing "no such table" errors during migration checks
          # Sequel's create_table? checks existence by attempting a SELECT,
          # which logs an error before being caught. This is expected behavior.
          suppress_table_check_errors(conn) do
            Sequel::Migrator.run(
              conn,
              migrations_dir,
              use_transactions: true,
              # PostgreSQL: Use advisory locks to prevent concurrent migration races
              # SQLite: No advisory lock support (single-instance deployments only)
              use_advisory_lock: conn.adapter_scheme == :postgres,
            )
          end
        ensure
          # Only disconnect if we created a separate connection
          if conn != database_connection
            conn.disconnect
          end
        end
      end

      # Temporarily suppress Sequel's logger to prevent confusing error logs
      # during table existence checks in migrations
      def suppress_table_check_errors(conn)
        original_loggers = conn.loggers.dup
        conn.loggers.clear
        yield
      ensure
        conn.loggers.clear
        original_loggers.each { |logger| conn.loggers << logger }
      end
    end
  end
end
