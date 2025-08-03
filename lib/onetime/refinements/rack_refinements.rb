# lib/onetime/refinements/rack_refinements.rb

module Onetime
  module RackRefinements # TODO: Remove when upgrading to Rack 3
    refine Hash do
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

      def dig(key, *rest)
        value = fetch(key, nil)  # Explicitly pass nil as default
        return value if rest.empty? || value.nil?

        value.respond_to?(:dig) ? value.dig(*rest) : nil
      end
    end
  end
end
