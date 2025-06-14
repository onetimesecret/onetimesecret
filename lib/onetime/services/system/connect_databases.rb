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
      Familia.uri = OT.conf[:redis][:uri]

      # Connect each model to its configured Redis database
      dbs = OT.conf.dig(:redis, :dbs)

      OT.ld "[connect_databases] dbs: #{dbs}"
      OT.ld "[connect_databases] models: #{Familia.members.map(&:to_s)}"

      # Validate that models have been loaded before attempting to connect
      if Familia.members.empty?
        raise Onetime::Problem, 'No known Familia members. Models need to load before calling boot!'
      end

      # Map model classes to their database numbers
      Familia.members.each do |model_class|
        model_sym = model_class.to_sym
        db_index  = dbs[model_sym] || DATABASE_IDS[model_sym] || 0 # see models.rb

        # Assign a Redis connection to the model class
        model_class.redis = Familia.redis(db_index)
        ping_result       = model_class.redis.ping

        OT.ld "Connected #{model_sym} to DB #{db_index} (#{ping_result})"
      end
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
      system_settings: 15,
    }
  end
end
