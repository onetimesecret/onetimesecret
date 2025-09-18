# lib/onetime/initializers/connect_databases.rb

require_relative '../refinements/horreum_refinements'

module Onetime
  module Initializers
    using Familia::HorreumRefinements

    # Connects each model to its configured Redis database.
    #
    # This method retrieves the Redis database configurations from the application
    # settings and establishes connections for each model class within the Familia
    # module. It assigns the appropriate Redis connection to each model and verifies
    # the connection by sending a ping command. Detailed logging is performed at each
    # step to facilitate debugging and monitoring.
    #
    # @example
    #   connect_databases
    #
    # @return [void]
    #
    def connect_databases
      Familia.uri = OT.conf['redis']['uri']

      # Connect each model to its configured Redis database
      dbs = OT.conf.dig('redis', 'dbs')

      OT.ld "[connect_databases] dbs: #{dbs}"
      OT.ld "[connect_databases] models: #{Familia.members.map(&:to_s)}"

      # Validate that models have been loaded before attempting to connect
      if Familia.members.empty?
        raise Onetime::Problem, 'No known Familia members. Models need to load before calling boot!'
      end

      # Map model classes to their database numbers
      Familia.members.each do |model_class|
        model_config_name = model_class.config_name
        db_index          = dbs[model_config_name] || 0

        # Assign a Redis connection to the model class
        model_class.dbclient = Familia.dbclient(db_index)
        ping_result       = model_class.dbclient.ping

        OT.ld "Connected #{model_config_name} to DB #{db_index} (#{ping_result})"
      end
    end
  end
end
