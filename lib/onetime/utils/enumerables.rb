# lib/onetime/utils/enumerables.rb

module Onetime
  module Utils
    module Enumerables


      # Standard deep_merge implementation with symbol/string key normalization
      #
      # TODO: The deep_merge method performs recursive merging without depth
      # limits or cycle detection. For large or deeply nested configurations,
      # this could lead to performance issues or stack overflow. Consider
      # adding safeguards. #1497
      #
      # @param original [Hash] Base hash with default values
      # @param other [Hash] Hash with values that override defaults
      # @return [Hash] A new hash containing the merged result with string keys
      def deep_merge(original, other)
        return normalize_keys(deep_clone(other)) if original.nil?
        return normalize_keys(deep_clone(original)) if other.nil?

        original_normalized = normalize_keys(deep_clone(original))
        other_normalized    = normalize_keys(deep_clone(other))

        merger = proc do |_key, v1, v2|
          if v1.is_a?(Hash) && v2.is_a?(Hash)
            v1.merge(v2, &merger)
          elsif v2.nil?
            v1
          else
            v2
          end
        end
        original_normalized.merge(other_normalized, &merger)
      end

      # Recursively freezes an object and all its nested components
      # to ensure complete immutability. This is a critical security
      # measure that prevents any modification of configuration values
      # after they've been loaded and validated, protecting against both
      # accidental mutations and potential security exploits.
      #
      # NOTE: This operates on the object itself, ensuring that all
      # nested components are also frozen. If you need to freeze an object
      # without modifying its original state, use `deep_clone` first
      # to avoid deep trouble.
      #
      # @param obj [Object] The object to freeze
      # @param clone [Boolean] Whether to clone the object before freezing
      # @return [Object] The frozen object
      # @security This ensures config values cannot be tampered with at runtime
      def deep_freeze(obj, clone = false)
        obj = deep_clone(obj) if clone # immediately forgets about the initial object
        case obj
        when Hash
          obj.each_value { |v| deep_freeze(v) }
        when Array
          obj.each { |v| deep_freeze(v) }
        end
        obj.freeze
      end

      # Creates a complete deep copy of a configuration hash using YAML
      # serialization. This ensures all nested objects are properly duplicated,
      # preventing unintended sharing of references that could lead to data
      # corruption if modified.
      #
      # @param config_hash [Hash] The configuration hash to be cloned
      # @return [Hash] A deep copy of the original configuration hash
      # @raise [OT::Problem] When YAML serialization fails due to unserializable
      #   objects
      # @security Prevents configuration mutations from affecting multiple
      #   components
      #
      # @security_note YAML Deserialization Restrictions
      #   Ruby's YAML parser (Psych) restricts object loading to prevent
      #   deserialization attacks. Only basic types are allowed by default:
      #   String, Integer, Float, Array, Hash, Symbol, Date, Time. Custom
      #   objects will raise Psych::DisallowedClass errors. Malicious alias
      #   references will raise Psych::BadAlias errors. These restrictions are
      #   intentional and provide security benefits by preventing malicious
      #   object deserialization and YAML bomb attacks in configuration data.
      #
      # @limitations
      #   - Only works with basic Ruby data types (String, Integer, Hash,
      #     Array, Symbol)
      #   - Custom objects, Struct instances, and complex classes are blocked
      #     for security
      #   - Objects with singleton methods or custom serialization will fail
      #   - Performance can degrade with deeply nested or large object
      #     structures
      #
      #   For configuration use cases, these limitations are beneficial as they
      #   ensure data integrity and prevent security vulnerabilities. Use
      #   recursive approaches for custom object cloning outside of
      #   configuration contexts.
      #
      def deep_clone(config_hash)
        # Since we know we only expect a regular hash here without any methods,
        # procs etc, we use YAML instead to accomplish the same thing (JSON is
        # another option but it turns all the symbol keys into strings).
        YAML.load(YAML.dump(config_hash)) # TODO: Use oj for perf and string gains
      rescue TypeError, Psych::DisallowedClass, Psych::BadAlias => ex
        raise OT::Problem, "[deep_clone] #{ex.message}"
      end

      # Dump structure with types instead of values. Used for safe logging of
      # configuration data to help debugging.
      # @param obj [Object] Any Ruby object
      # @return [Hash,Array,String] Structure with class names instead of values
      def type_structure(obj)
        case obj
        when Hash
          obj.transform_values { |v| type_structure(v) }
            .transform_values { |v| v.is_a?(Hash) ? v : v.to_s }
        when Array
          if obj.empty?
            'Array<empty>'
          else
            sample = type_structure(obj.first)
            "Array<#{sample.class.name}>"
          end
        when NilClass
          'nil'
        else
          obj.class.name
        end
      end

      private

      # Recursively normalizes hash keys to strings to ensure consistent key types
      # and prevent symbol/string key conflicts during merging operations.
      #
      # @param obj [Object] The object to normalize (Hash, Array, or other)
      # @return [Object] The object with normalized string keys
      def normalize_keys(obj)
        case obj
        when Hash
          normalized = {}
          obj.each do |key, value|
            normalized[key.to_s] = normalize_keys(value)
          end
          normalized
        when Array
          obj.map { |item| normalize_keys(item) }
        else
          obj
        end
      end

    end
  end
end
