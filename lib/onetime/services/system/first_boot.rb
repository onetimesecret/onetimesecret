# lib/onetime/services/system/merge_config.rb

module Onetime
  module Services
    module System

      # First Boot Provider
      #
      # Responsible for detecting whether this is the first time this
      # app is booting up with an empty database. Or if not, but there
      # is no existing MutableSettings record in redis, it will read the
      # defaults from etc/mutable_settings.yaml and create one.
      #
      # If it is the first boot, it will print out some helpful information
      # to the user if there is any sort of error starting up.
      #
      # After that it simply checks that MutableSettings.current record
      # exists and is not empty. This provider is transitional and can
      # eventually be removed once there is a low chance any installs
      # still need to upgrade. Or after a sufficiently long time.
      class FirstBoot < ServiceProvider
        @base_path                     = ENV.fetch('ONETIME_HOME').freeze
        @mutable_settings_defaults_path = File.join(@base_path, 'etc', 'mutable_settings.yaml').freeze

        class << self
          attr_reader :base_path, :mutable_settings_defaults_path
        end

        def initialize
          super(:first_boot, type: TYPE_CONFIG, priority: 20)
          @first_boot = nil
        end

        # Sets up system settings by checking for existing override
        # configuration in Redis and merging it with YAML configuration.
        # Creates initial system settings record on first boot.
        #
        def start(config)
          OT.ld '[BOOT.first_boot] Setting up system settings...'

          # Check if this is the first boot by looking for existing data
          is_first_boot = detect_first_boot
          OT.ld "[BOOT.first_boot] First boot detected: #{is_first_boot}"

          # Check for existing system settings
          dynamic_config = begin
            V2::MutableSettings.current
          rescue OT::RecordNotFound => ex
            OT.ld "[BOOT.first_boot] No existing system settings found: #{ex.message}"
            nil
          end

          if dynamic_config
            OT.li "[BOOT.first_boot] Found existing system settings: #{dynamic_config.rediskey}"
            # Merge existing system settings with YAML configuration
            # merge_mutable_settings(dynamic_config)

          else
            # Create initial system settings from current YAML configuration
            create_initial_mutable_settings(config)
          end
        rescue Redis::CannotConnectError => ex
          OT.lw "[BOOT.first_boot] Cannot connect to Redis for system settings setup: #{ex.message}"
          OT.lw '[BOOT.first_boot] Falling back to YAML configuration only'
        rescue StandardError => ex
          OT.le "[BOOT.first_boot] Error during system settings setup: #{ex.message}"
          OT.ld ex.backtrace.join("\n")
          OT.lw '[BOOT.first_boot] Falling back to YAML configuration only'
        ensure
          if is_first_boot
            OT.lw <<~BOOT
              Have you run the 1452 migration yet? Run:
                    `bundle exec bin/ots migrate --run 1452`

              If you have, make sure etc/config.yaml and mutable_settings.yaml
              files exist. In a pinch you can copy the files from etc/defaults
              to etc/ (just remove the "defaults." in the name).
            BOOT
          end
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
        def create_initial_mutable_settings(_config)
          OT.ld '[BOOT.first_boot] Creating initial system settings from YAML...'

          path             = self.class.mutable_settings_defaults_path
          default_settings = OT::Configurator::Load.yaml_load_file(path)

          raise 'Missing required settings' if (default_settings || {}).empty?

          # mutable_settings_data           = V2::MutableSettings.extract_mutable_settings(OT.conf)
          default_settings[:comment] = "Initial configuration via #{path}"
          default_settings[:custid]  = nil # No customer owner for initial config

          new_config = V2::MutableSettings.create(**default_settings)
          OT.ld "[BOOT.first_boot] Created initial system settings: #{new_config.rediskey}"
        end

      end
    end
  end
end
