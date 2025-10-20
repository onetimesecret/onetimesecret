# apps/web/auth/config/database.rb

require 'sequel'
require 'logger'

module Auth
  module Config
    module Database
      def self.connection
        # Only create database connection in advanced mode
        # Basic mode operates without SQL database dependencies
        return nil unless Onetime.auth_config.advanced_enabled?

        @connection ||= create_connection
      end

      # Session configuration is now centralized in apps/middleware_stack.rb
      #
      # def self.session_config
      #   {
      #     expire_after: 86_400, # 24 hours
      #     key: 'onetime.session',  # Unified cookie name
      #     secure: ENV['RACK_ENV'] == 'production',
      #     httponly: true,
      #     same_site: :strict,
      #     redis_prefix: 'session',
      #   }
      # end

      private_class_method def self.create_connection
        # Get database URL from auth config or environment
        database_url = Onetime.auth_config.database_url ||
                      ENV['DATABASE_URL'] ||
                      'sqlite://data/auth.db'

        db = Sequel.connect(database_url)

        # Enable SQL logging in development
        if ENV['RACK_ENV'] == 'development'
          db.loggers << Logger.new($stdout)
        end

        db
      end
    end
  end
end
