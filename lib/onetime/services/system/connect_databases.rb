# lib/onetime/services/system/connect_databases.rb


require 'onetime/refinements/horreum_refinements'

module Onetime
  module Services
    module System

      class ConnectDatabases < ServiceProvider
        using Familia::HorreumRefinements

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

          # Connect each model to its configured Redis database
          db_map = db_settings['database_mapping']

          debug "db_map: #{db_map}"
          debug "models: #{Familia.members.map(&:to_s)}"

          # Validate that models have been loaded before attempting to connect
          if Familia.members.empty?
            raise Onetime::Problem, 'No known Familia members. Models need to load before calling boot!'
          end

          # Map model classes to their database numbers
          Familia.members.each do |model_class|
            model_sym = model_class.to_sym
            db_index  = db_map[model_sym] || DATABASE_IDS[model_sym] || 0 # see models.rb

            # Assign a Redis connection to the model class
            model_class.redis = Familia.redis(db_index)
            ping_result       = model_class.redis.ping

            debug "Connected #{model_sym} to DB #{db_index} (#{ping_result})"
          end

          # Register successful connection
          register_provider(:databases, :connected)
        end

        ##
        # Health check - verify database connections are still alive
        #
        # @return [Boolean] true if all connections are healthy
        def healthy?
          return false unless super

          # Check a sample of connections to verify they're still alive
          Familia.members.sample(3).all? do |model_class|
            model_class.redis.ping == 'PONG'
          rescue StandardError
            false
          end
        rescue StandardError
          false
        end

        # For backwards compatibility with v0.18.3 and earlier, these redis database
        # IDs had been hardcoded in their respective model classes which we maintain
        # here for existing installs. If they haven't had a chance to update their
        # etc/config.yaml files OR
        #
        # For installs running via docker image + environment vars, this change should
        # be a non-issue as long as the default config (etc/examples/config.example.yaml) is
        # used (which it is in the official images).
        #
        DATABASE_IDS = {
          session: 1,
          splittest: 1,
          ratelimit: 2,
          custom_domain: 6,
          customer: 6,
          subdomain: 6,
          metadata: 7,
          email_receipt: 8,
          secret: 8,
          feedback: 11,
          exception_info: 12,
          mutable_config: 15,
        }
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
