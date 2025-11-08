# lib/onetime/utils/enumerables.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    module Enumerables
      # Maximum recursion depth for safety
      DEFAULT_MAX_DEPTH = 25
      DEFAULT_MAX_SIZE  = 2 * 1024 * 1024 # 2MB

      # Standard deep_merge implementation with symbol/string key normalization
      # and depth limiting for safety
      #
      # @param original [Hash] Base hash with default values
      # @param other [Hash] Hash with values that override defaults
      # @param max_depth [Integer] Maximum recursion depth (default: 25)
      # @return [Hash] A new hash containing the merged result with string keys
      # @raise [OT::Problem] When max depth is exceeded
      def deep_merge(original, other, max_depth: DEFAULT_MAX_DEPTH)
        return normalize_keys(deep_clone(other)) if original.nil?
        return normalize_keys(deep_clone(original)) if other.nil?

        original_normalized = normalize_keys(deep_clone(original))
        other_normalized    = normalize_keys(deep_clone(other))

        merger = proc do |_key, v1, v2, depth = 0|
          _check_max_depth(depth, max_depth)

          if v1.is_a?(Hash) && v2.is_a?(Hash)
            v1.merge(v2) { |k, val1, val2| merger.call(k, val1, val2, depth + 1) }
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
      # @param obj [Object] The object to freeze
      # @param clone [Boolean] Whether to clone the object before freezing (default: false)
      # @param max_depth [Integer] Maximum recursion depth (default: 25)
      # @return [Object] The frozen object (original if clone=false, copy if clone=true)
      # @raise [OT::Problem] When max depth is exceeded
      # @security This ensures config values cannot be tampered with at runtime
      # @note When clone=false, operates on the object itself. When clone=true,
      #   operates on a deep copy, leaving the original untouched.
      def deep_freeze(obj, clone = false, max_depth: DEFAULT_MAX_DEPTH)
        obj = deep_clone(obj) if clone
        _deep_freeze_recursive(obj, 0, max_depth)
      end

      # Creates a complete deep copy using YAML with size checking
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
      # @param config_hash [Hash] The configuration hash to be cloned
      # @param max_size [Integer] Maximum serialized size in bytes (default: 2MB)
      # @return [Hash] A deep copy of the original configuration hash
      # @raise [OT::Problem] When YAML serialization fails or size exceeds limit

      def deep_clone(config_hash, max_size: DEFAULT_MAX_SIZE)
         # Since we know we only expect a regular hash here without any methods,
         # procs etc, we use YAML instead to accomplish the same thing (JSON is
         # another option but it turns all the symbol keys into strings).
         yaml_str = YAML.dump(config_hash)

         if yaml_str.bytesize > max_size
           raise OT::Problem, "serialized size #{yaml_str.bytesize} exceeds limit #{max_size}"
         end

         YAML.load(yaml_str)
      rescue TypeError, Psych::DisallowedClass, Psych::BadAlias => ex
         raise OT::Problem, "[deep_clone] #{ex.message}"
      end

      # Dump structure with types instead of values
      # @param obj [Object] Any Ruby object
      # @param max_depth [Integer] Maximum recursion depth (default: 25)
      # @return [Hash,Array,String] Structure with class names instead of values
      def type_structure(obj, max_depth: DEFAULT_MAX_DEPTH)
        _type_structure_recursive(obj, 0, max_depth)
      end

      private

        # Internal recursive implementation for deep_freeze with depth tracking
        def _deep_freeze_recursive(obj, depth, max_depth)
          _check_max_depth(depth, max_depth)

          case obj
          when Hash
            obj.each_value { |v| _deep_freeze_recursive(v, depth + 1, max_depth) }
          when Array
            obj.each { |v| _deep_freeze_recursive(v, depth + 1, max_depth) }
          end
          obj.freeze
        end

        # Internal recursive implementation for type_structure with depth tracking
        def _type_structure_recursive(obj, depth, max_depth)
          return '<<MAX_DEPTH_EXCEEDED>>' if depth >= max_depth

          case obj
          when Hash
            obj.transform_values { |v| _type_structure_recursive(v, depth + 1, max_depth) }
              .transform_values { |v| v.is_a?(Hash) ? v : v.to_s }
          when Array
            if obj.empty?
              'Array<empty>'
            else
              sample = _type_structure_recursive(obj.first, depth + 1, max_depth)
              "Array<#{sample.class.name}>"
            end
          when NilClass
            'nil'
          else
            obj.class.name
          end
        end

        # Recursively normalizes hash keys with depth limiting
        #
        # This method is already private, so adding depth parameters doesn't
        # pollute the public API.
        def normalize_keys(obj, depth = 0, max_depth = DEFAULT_MAX_DEPTH)
          _check_max_depth(depth, max_depth)

          case obj
          when Hash
            normalized = {}
            obj.each do |key, value|
              normalized[key.to_s] = normalize_keys(value, depth + 1, max_depth)
            end
            normalized
          when Array
            obj.map { |item| normalize_keys(item, depth + 1, max_depth) }
          else
            obj
          end
        end

        def _check_max_depth(depth, max_depth)
          raise OT::Problem, "exceeded max depth of #{max_depth}" if depth >= max_depth
        end
    end
  end
end
