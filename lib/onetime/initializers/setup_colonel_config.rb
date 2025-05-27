# lib/onetime/initializers/setup_colonel_config.rb

module Onetime
  module Initializers

    # Sets up colonel configuration by checking for existing override
    # configuration in Redis and merging it with YAML configuration.
    # Creates initial colonel config record on first boot.
    #
    def setup_colonel_config
      OT.li "Setting up colonel configuration..."

      # Check if this is the first boot by looking for existing data
      is_first_boot = detect_first_boot
      OT.li "First boot detected: #{is_first_boot}"

      # Check for existing colonel config
      existing_config = begin
        V2::ColonelConfig.current
      rescue OT::RecordNotFound => e
        OT.li "No existing colonel config found: #{e.message}"
        nil
      end

      if existing_config
        OT.li "Found existing colonel config: #{existing_config.rediskey}"
        # Merge existing colonel config with YAML configuration
        merge_colonel_config(existing_config)

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
      OT.li "Creating initial colonel config from YAML..."

      colonel_config_data = extract_colonel_sections(OT.conf)
      colonel_config_data[:comment] = "Initial configuration"
      colonel_config_data[:custid] = nil # No customer owner for initial config

      new_config = V2::ColonelConfig.create(**colonel_config_data)
      OT.li "Created initial colonel config: #{new_config.rediskey}"
    end

    # Merges colonel config values into the main configuration
    def merge_colonel_config(colonel_config)
      OT.li "Merging colonel config #{colonel_config.rediskey} with YAML configuration"

      sections_overridden = []

      # Map colonel config fields to their configuration paths
      field_mappings = {
        interface: [:site, :interface],
        secret_options: [:site, :secret_options],
        mail: [:mail],
        limits: [:limits],
        experimental: [:experimental],
        diagnostics: [:diagnostics],
      }

      field_mappings.each do |field, config_path|
        colonel_value = colonel_config.send(field)
        next if colonel_value.nil? || colonel_value.empty?

        # Parse JSON if it's a string (for complex fields)
        parsed_value = colonel_value.is_a?(String) ? JSON.parse(colonel_value) : colonel_value

        # Deep merge the value into the configuration
        set_deep_config_value(OT.conf, config_path, parsed_value)
        sections_overridden << config_path.join('.')
      end

      if sections_overridden.any?
        OT.li "Colonel config overrode sections: #{sections_overridden.join(', ')}"
      else
        OT.li "Colonel config present but no sections overridden"
      end
    end

    # Extracts the sections that colonel config manages from the full config
    def extract_colonel_sections(config)
      {
        interface: config.dig(:site, :interface),
        secret_options: config.dig(:site, :secret_options),
        mail: config[:mail],
        limits: config[:limits],
        experimental: config[:experimental],
        diagnostics: config[:diagnostics],
      }
    end

    # Sets a value deep in a nested hash structure
    def set_deep_config_value(config, path, value)
      path[0..-2].inject(config) { |h, key| h[key] ||= {} }[path.last] = value
    end

  end
end
