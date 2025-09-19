# lib/onetime/initializers/connect_databases.rb

require_relative '../refinements/horreum_refinements'
require_relative 'detect_legacy_data'

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
      # Check for legacy data distribution before connecting to databases
      legacy_data = detect_legacy_data
      warn_about_legacy_data(legacy_data)

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
      #
      # NOTE: This can appear in the boot log like ther models are duplicated
      # but it's just the V1 + V2 models which share the same model_config_name.
      # We are technically duplicating effort since both versions share the same
      # database but it's not hurting anyone and it won't be forever.
      Familia.members.each do |model_class|
        model_config_name = model_class.config_name
        db_index          = dbs[model_config_name] || 0

        # Assign a Redis connection to the model class
        model_class.dbclient = Familia.dbclient(db_index)
        ping_result          = model_class.dbclient.ping

        OT.ld "Connected #{model_config_name} to DB #{db_index} (#{ping_result})"

        # Save a flag in each model DB to signal a data migration will be
        # needed for existing data. If the database is already 0, no need.
        next unless db_index.positive?

        dbkey = Familia.join(['ots', 'migration_needed', model_config_name, "db_#{db_index}"])
        first_time = model_class.dbclient.setnx(dbkey, '1')
        OT.ld "[connect_databases] Setting #{dbkey} to '1' (already set? #{!first_time})"
      end
    end
  end
end
