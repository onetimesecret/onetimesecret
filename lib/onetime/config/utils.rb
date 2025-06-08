# lib/onetime/config/utils.rb

require 'json_schemer'

module Onetime
  class Config

    unless defined?(KNOWN_PATHS)
      KNOWN_PATHS = %w[/etc/onetime ./etc ~/.onetime].freeze

      KEY_MAP = {
        allowed_domains_only: :whitelist_validation,
        allowed_emails: :whitelisted_emails,
        blocked_emails: :blacklisted_emails,
        allowed_domains: :whitelisted_domains,
        blocked_domains: :blacklisted_domains,
        blocked_mx_ip_addresses: :blacklisted_mx_ip_addresses,

        # An example mapping for testing.
        example_internal_key: :example_external_key,
      }
    end

    module Utils
      extend self

      def validate_with_schema(conf, schema)

        # Create schema validator with defaults insertion enabled
        schemer = JSONSchemer.schema(
          schema,
          meta_schema: 'https://json-schema.org/draft/2020-12/schema',
          insert_property_defaults: true,
          format: true,

          # For fields that we validate as strings, if the value is a symbol
          # we convert it to a string to during validation.
          # NOTE: We intentionally do this for symbols->strings only for backwards
          # compatability of our YAML configuration where historically we've used
          # symbols to represent certain values.
          before_property_validation: proc do |data, property, property_schema, _parent|
            val = data[property]
            case property_schema["type"]
            when "string"
              data[property] = val.to_s if val.is_a?(Symbol)
            end
          end,
        )

        # Validate and collect errors
        errors = schemer.validate(conf).to_a
        return conf if errors.empty? # return modified configuration

        # Format error messages
        error_messages = format_validation_errors(errors)

        # Extract problem paths
        error_paths = extract_error_paths(errors)

        # Raise a structured error object instead of just a string message
        raise OT::ConfigValidationError.new(
          messages: error_messages,
          paths: error_paths,
        )
      end

      # Formats validation errors into user-friendly messages
      def format_validation_errors(errors)
        errors.map do |err|
          err['error']
        end
      end

      # Extracts the paths and values that failed validation
      def extract_error_paths(errors)
        error_paths = {}
        errors.each do |err|
          path_segments = err['data_pointer'].split('/').reject(&:empty?)
          next if path_segments.empty?

          # Navigate to proper nesting level
          current = error_paths
          parent_segments = path_segments[0..-2]
          parent_segments.each do |segment|
            current[segment] ||= {}
            current = current[segment]
          end

          # Add value at this path
          current[path_segments.last] = err['data']
        end
        error_paths
      end

      def mapped_key(key)
        # `key` is a symbol. Returns a symbol.
        # If the key is not in the KEY_MAP, return the key itself.
        KEY_MAP[key] || key
      end

      # Applies default values to its config level peers
      #
      # @param config [Hash] Configuration with top-level section keys, including a :defaults key
      # @return [Hash] Configuration with defaults applied to each section, with :defaults removed
      #
      # This method extracts defaults from the :defaults key and applies them to each section:
      # - Section values override defaults (except nil values, which use defaults)
      # - The :defaults section is removed from the result
      # - Only Hash-type sections receive defaults
      #
      # @example Basic usage
      #   config = {
      #     defaults: { timeout: 5, enabled: true },
      #     api: { timeout: 10 },
      #     web: { theme: 'dark' }
      #   }
      #   apply_defaults_to_peers(config)
      #   # => { api: { timeout: 10, enabled: true },
      #   #      web: { theme: 'dark', timeout: 5, enabled: true } }
      #
      # @example Edge cases
      #   apply_defaults_to_peers({a: {x: 1}})                # => {a: {x: 1}}
      #   apply_defaults_to_peers({defaults: {x: 1}, b: {}})  # => {b: {x: 1}}
      #
      def apply_defaults_to_peers(config={})
        return {} if config.nil? || config.empty?

        # Extract defaults from the configuration (handle both symbol and string keys)
        defaults = config[:defaults] || config['defaults']

        # If no valid defaults exist, return config without the :defaults key
        unless defaults.is_a?(Hash)
          result = {}
          config.each do |key, value|
            next if key == :defaults || key == 'defaults'
            # Normalize the value to string keys using deep_merge with empty hash
            result[key.to_s] = value.is_a?(Hash) ? OT::Utils.deep_merge({}, value) : value
          end
          return result
        end

        # Process each section, applying defaults
        config.each_with_object({}) do |(section, values), result|
          # Skip the :defaults key (handle both symbol and string)
          next if section == :defaults || section == 'defaults'
          next unless values.is_a?(Hash) # Process only sections that are hashes

          # Apply defaults to each section, normalize section key to string
          result[section.to_s] = OT::Utils.deep_merge(defaults, values)
        end
      end



    end


  end
end
