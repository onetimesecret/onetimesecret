# apps/web/auth/database.rb
#
# frozen_string_literal: true

require 'sequel'
require 'logger'

require_relative 'migrator'

module Auth
  module Database
    extend Onetime::LoggerMethods

    def self.connection
      # Only create database connection in full mode
      # Simple mode operates without SQL database dependencies
      return nil unless Onetime.auth_config.full_enabled?

      @connection ||= create_connection
    end

    def self.create_connection
      sequel_logger.info '[Database] Creating Auth database connection'

      # Get database URL from auth config or environment
      database_url = Onetime.auth_config.database_url || 'sqlite://data/auth.db'

      Sequel.connect(
        database_url,
        logger: Onetime.get_logger('Sequel'),
        sql_log_level: :trace,  # Log SQL statements at trace level for safety
      )
    end
  end
end
