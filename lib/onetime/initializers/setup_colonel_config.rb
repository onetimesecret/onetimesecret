# lib/onetime/initializers/setup_colonel_config.rb

module Onetime
  module Initializers
    @first_boot = nil

    # Sets up colonel configuration by checking for existing override
    # configuration in Redis and merging it with YAML configuration.
    # Creates initial colonel config record on first boot.
    #
    def setup_colonel_config
      OT.ld "Setting up colonel configuration..."

      # Check if this is the first boot by looking for existing data
      is_first_boot = detect_first_boot
      OT.ld "First boot detected: #{is_first_boot}"

      # Check for existing colonel config
      existing_config = begin
        V2::ColonelConfig.current
      rescue OT::RecordNotFound => e
        OT.ld "No existing colonel config found: #{e.message}"
        nil
      end

      if existing_config
        OT.ld "Found existing colonel config: #{existing_config.rediskey}"
        # Merge existing colonel config with YAML configuration
        # merge_colonel_config(existing_config)

      elsif existing_config.nil?
        # Create initial colonel config from current YAML configuration
        create_initial_colonel_config
      else
        OT.lw "Not sure how we got here"
      end

    rescue Redis::CannotConnectError => e
      OT.lw "Cannot connect to Redis for colonel config setup: #{e.message}"
      OT.lw "Falling back to YAML configuration only"
    rescue StandardError => e
      OT.le "Error during colonel config setup: #{e.message}"
      OT.ld e.backtrace.join("\n")
      OT.lw "Falling back to YAML configuration only"
    end

    private

    # Detects if this is the first boot by checking for existing data
    # in key model classes. If any of the checks return true, it indicates
    # there are existing records so the system is not in its initial state.
    def detect_first_boot
      model_checks = [
        -> { V2::Metadata.redis.scan_each(match: 'metadata:*').first },
        -> { V2::Customer.values.element_count > 0 },
        -> { V2::Session.values.element_count > 0 },
      ]
      model_checks.none? do |lambda|
        lambda.call
      end
    end

    # Creates initial colonel config record from current YAML configuration
    def create_initial_colonel_config
      OT.ld "Creating initial colonel config from YAML..."

      colonel_config_data = V2::ColonelConfig.extract_colonel_config(OT.conf)
      colonel_config_data[:comment] = "Initial configuration"
      colonel_config_data[:custid] = nil # No customer owner for initial config

      new_config = V2::ColonelConfig.create(**colonel_config_data)
      OT.ld "Created initial colonel config: #{new_config.rediskey}"
    end

    # Applies colonel config on top of the main configuration, where the colonel
    # config overrides the main configuration.
    def apply_colonel_config(colonel_config)


      onetime_config_data = colonel_config.to_onetime_config

      # Makes a deep copy of OT.conf, then merges the colonel config data, and
      # replaces OT.config with the merged data.
      Onetime.apply_config(onetime_config_data)

    end

  end
end
