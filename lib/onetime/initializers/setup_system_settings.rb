# lib/onetime/initializers/setup_system_settings.rb

module Onetime
  module Initializers
    @first_boot = nil

    # Sets up system settings by checking for existing override
    # configuration in Redis and merging it with YAML configuration.
    # Creates initial system settings record on first boot.
    #
    def setup_system_settings
      OT.ld "Setting up system settings..."

      # Check if this is the first boot by looking for existing data
      is_first_boot = detect_first_boot
      OT.ld "First boot detected: #{is_first_boot}"

      # Check for existing system settings
      existing_config = begin
        V2::SystemSettings.current
      rescue OT::RecordNotFound => e
        OT.ld "No existing system settings found: #{e.message}"
        nil
      end

      if existing_config
        OT.ld "Found existing system settings: #{existing_config.rediskey}"
        # Merge existing system settings with YAML configuration
        # merge_system_settings(existing_config)

      elsif existing_config.nil?
        # Create initial system settings from current YAML configuration
        create_initial_system_settings
      else
        OT.lw "Not sure how we got here"
      end

    rescue Redis::CannotConnectError => e
      OT.lw "Cannot connect to Redis for system settings setup: #{e.message}"
      OT.lw "Falling back to YAML configuration only"
    rescue StandardError => e
      OT.le "Error during system settings setup: #{e.message}"
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

    # Creates initial system settings record from current YAML configuration
    def create_initial_system_settings
      OT.ld "Creating initial system settings from YAML..."

      system_settings_data = V2::SystemSettings.extract_system_settings(OT.conf)
      system_settings_data[:comment] = "Initial configuration"
      system_settings_data[:custid] = nil # No customer owner for initial config

      new_config = V2::SystemSettings.create(**system_settings_data)
      OT.ld "Created initial system settings: #{new_config.rediskey}"
    end

    # Applies system settings on top of the main configuration, where the colonel
    # config overrides the main configuration.
    def apply_system_settings(system_settings)


      onetime_config_data = system_settings.to_onetime_config

      # Makes a deep copy of OT.conf, then merges the system settings data, and
      # replaces OT.config with the merged data.
      Onetime.apply_config(onetime_config_data)

    end

  end
end
