# frozen_string_literal: true

require 'sequel'
require 'logger'

module Auth
  module Config
    module Database
      def self.connection
        @connection ||= create_connection
      end

      def self.session_config
        {
          expire_after: 86_400, # 24 hours
          key: 'onetime.session',  # Unified cookie name
          secure: ENV['RACK_ENV'] == 'production',
          httponly: true,
          same_site: :lax,
          redis_prefix: 'session'
        }
      end

      private_class_method def self.create_connection
        database_url = ENV['DATABASE_URL'] || 'sqlite://data/auth.db'
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
