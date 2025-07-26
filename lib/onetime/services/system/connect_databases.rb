# lib/onetime/services/system/connect_databases.rb


require 'onetime/refinements/horreum_refinements'

module Onetime
  module Services
    module System

      class ConnectDatabases < ServiceProvider
        using Familia::HorreumRefinements # for `model_class.to_s`, see below

        def initialize
          super(:connect_databases, type: TYPE_CONNECTION, priority: 5) # High priority - other services depend on DB
        end

        ##
        # Connects each model to its configured Redis database.
        #
        # This method retrieves the Redis database configurations from the application
        # settings and establishes connections for each model class within the Familia
        # module. It assigns the appropriate Redis connection to each model and verifies
        # the connection by sending a ping command. Detailed logging is performed at each
        # step to facilitate debugging and monitoring.
        #
        # @param config [Hash] Application configuration
        # @return [void]
        #
        def start(config)

          db_settings = config.dig('storage', 'db')
          Familia.uri = db_settings['connection']['url']

          # Validate that models have been loaded before attempting to connect
          familia_members = Familia.members
          if familia_members.empty?
            raise Onetime::Problem, 'No known Familia members. Models need to load before calling boot!'
          end

          # Connect each model to its configured Redis database.
          # We normalize to strings instead of symbols to be consistent with
          # the rest of the codebase that interacts with config.
          db_map = db_settings['database_mapping'].transform_keys(&:to_s)

          debug "models: #{familia_members}"
          debug "db_map: #{db_map}"

          # Map model classes to their database numbers
          familia_members.each do |model_class|
            model_str = model_class.config_name
            db_index  = db_map[model_str] || 0 # If not specified in config, use zero

            # Assign a Redis connection to the model class
            model_class.dbclient = Familia.dbclient(db_index)
            ping_result       = model_class.dbclient.ping

            debug "Connected #{model_str} to DB #{db_index} (#{ping_result})"
          end

          # Register successful connection
          ServiceRegistry.register_provider(:databases, :connected)
        end

        ##
        # Health check - verify database connections are still alive
        #
        # @return [Boolean] true if all connections are healthy
        def healthy?
          return false unless super

          # Check a sample of connections to verify they're still alive
          Familia.members.sample(3).all? do |model_class|
            model_class.dbclient.ping == 'PONG'
          rescue StandardError
            false
          end
        rescue StandardError
          false
        end
      end

      # Legacy method for backward compatibility
      # def connect_databases(config)
      #   provider = ConnectDatabases.new
      #   provider.start_internal(config)
      #   provider
      # end
    end
  end
end
