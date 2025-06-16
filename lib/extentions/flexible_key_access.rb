# lib/extentions/flexible_key_access.rb

module Extensions
  # Module providing flexible key access for Hash objects
  #
  # Usage:
  #   hash = { name: "John" }
  #   hash.extend(FlexibleKeyAccess)
  #
  #   hash[:name]  # => "John"
  #   hash["name"] # => "John"
  #   hash.key?(:name)  # => true
  #   hash.key?("name") # => true
  module FlexibleKeyAccess
    # Access hash values with string or symbol keys interchangeably
    # @param key [Object] key to look up
    # @return [Object, nil] value for the key in any of its forms
    def [](key)
      super || super(key.to_s) || super(key.to_sym)
    end

    # Check if hash contains a key in any of its string/symbol forms
    # @param key [Object] key to check
    # @return [Boolean] true if key exists in any form
    def key?(key)
      super || super(key.to_s) || super(key.to_sym)
    end
  end
end
