# lib/onetime/refinements/rack_refinements.rb
# rubocop:disable

module Onetime
  module RackRefinements
    refine Hash do
      def fetch(key, *args)
        OT.ld "[Hash#fetch] key: #{key}, args: #{args}"
        string_key = key.to_s
        symbol_key = key.respond_to?(:to_sym) ? key.to_sym : nil

        if key?(string_key)
          super(string_key, *args)
        elsif symbol_key && key?(symbol_key)
          super(symbol_key, *args)
        elsif block_given?
          yield key
        elsif args.any?
          args.first
        else
          raise KeyError, "key not found: #{key.inspect}"
        end
      end

      def dig(key, *rest)
        OT.ld "[Hash#dig] key: #{key}, rest: #{rest}"
        value = fetch(key, nil)  # Explicitly pass nil as default
        return value if rest.empty? || value.nil?
        value.respond_to?(:dig) ? value.dig(*rest) : nil
      end
    end
  end
end
