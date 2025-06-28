# apps/api/v1/refinements.rb

module Onetime
  # RackRefinements provides enhanced Hash methods for handling web request
  # parameters and data structures commonly used in Rack-based applications.
  #
  # NOTE: This code although deprecated is still kept for v1 compatibility. The
  # legacy v1 API is in maintenance mode warts and all. It's been around for
  # over 10 years so there are a lot of inbound integrations with other systems.
  # Until we have a specific migration plan in place, this module will continue
  # to be maintained for the society of creative anachronisms.
  #
  # @deprecated This module duplicates functionality found in
  # IndifferentHashAccess (indifferent_hash_access.rb). Both provide string/symbol
  # indifferent key access for Hash objects. IndifferentHashAccess has since
  # been removed and this one should as well.
  #
  # **Comparison with IndifferentHashAccess:**
  # - Both enable string/symbol indifferent key access
  # - Both override `fetch` and `dig` methods
  # - Both handle the same core use case for web parameters
  #
  # **Key Differences:**
  # 1. **Error handling**: RackRefinements has explicit KeyError raising,
  #    while IndifferentHashAccess delegates to original method
  # 2. **Implementation**: RackRefinements converts keys then checks existence;
  #    IndifferentHashAccess uses has_key? checks before conversion
  # 3. **Coverage**: IndifferentHashAccess also overrides [] operator
  #
  module RackRefinements
    refine Hash do
      # Enhanced fetch method that tries both string and symbol versions of keys.
      #
      # This method first attempts to find the key as-is, then tries converting
      # between string and symbol representations. This is particularly useful
      # for web applications where parameter keys might be received as strings
      # but accessed as symbols (or vice versa).
      #
      # @param key [Object] The key to look up
      # @param args [Array] Default value(s) to return if key not found
      # @return [Object] The value associated with the key
      # @raise [KeyError] If key not found and no default provided
      #
      # @example
      #   hash = { "name" => "John", age: 30 }
      #   hash.fetch(:name)    # => "John" (finds string key "name")
      #   hash.fetch("age")    # => 30 (finds symbol key :age)
      def fetch(key, *args)
        string_key = key.to_s
        symbol_key = key.respond_to?(:to_sym) ? key.to_sym : nil
        return super(string_key, *args) if key?(string_key)
        return super(symbol_key, *args) if symbol_key && key?(symbol_key)
        return yield(key) if block_given?
        return args.first unless args.empty?
        return nil if args == [nil]  # Handle explicit nil default

        raise KeyError, "key not found: #{key.inspect}"
      end

      # Enhanced dig method that uses the refined fetch behavior.
      #
      # Like the standard Hash#dig, but leverages the enhanced fetch method
      # to provide flexible key lookup (string/symbol interchangeability) at
      # each level of digging.
      #
      # @param key [Object] The first key to look up
      # @param rest [Array] Additional keys to dig deeper into nested structures
      # @return [Object, nil] The value found by digging, or nil if any key is missing
      #
      # @example
      #   hash = { "user" => { name: "John", "details" => { age: 30 } } }
      #   hash.dig(:user, "name")              # => "John"
      #   hash.dig("user", :details, "age")    # => 30
      def dig(key, *rest)
        value = fetch(key, nil)  # Explicitly pass nil as default
        return value if rest.empty? || value.nil?

        value.respond_to?(:dig) ? value.dig(*rest) : nil
      end
    end
  end
end
