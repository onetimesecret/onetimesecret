# lib/onetime/indifferent_hash.rb
#
# frozen_string_literal: true

module Onetime
  # Hash subclass providing indifferent access (symbol or string keys)
  # Used to wrap configuration loaded from YAML files.
  #
  # PURPOSE: Temporary compatibility layer for main branch migration.
  # Allows existing symbol-key config access while develop enforces string keys.
  # Remove after develop merge when all config access uses string keys.
  #
  # LIMITATIONS (do not use for general-purpose indifferent hashing):
  # - Only converts symbol keys to strings; other key types pass through
  # - clone() not overridden (use dup instead)
  # - select/reject/transform_* return plain Hash, not IndifferentHash
  # - merge! block receives string keys regardless of input key type
  #
  # For production indifferent access, use hashie gem or similar.
  #
  # @example
  #   config = IndifferentHash.deep_convert({ site: { host: 'example.com' } })
  #   config[:site][:host]      # => 'example.com'
  #   config['site']['host']    # => 'example.com'
  #   config.dig(:site, 'host') # => 'example.com'
  #
  # TODO: To be removed after develop merged in to main.
  #
  class IndifferentHash < Hash
    def self.deep_convert(obj)
      case obj
      when Hash
        new.tap do |h|
          obj.each { |k, v| h[k.to_s] = deep_convert(v) }
        end
      when Array
        obj.map { |v| deep_convert(v) }
      else
        obj
      end
    end

    def [](key)
      super(convert_key(key))
    end

    def []=(key, value)
      super(convert_key(key), value)
    end

    def dig(key, *rest)
      value = self[key]
      return value if rest.empty? || value.nil?
      return value.dig(*rest) if value.respond_to?(:dig)
      nil
    end

    def fetch(key, ...)
      super(convert_key(key), ...)
    end

    def key?(key)
      super(convert_key(key))
    end
    alias has_key? key?
    alias include? key?
    alias member? key?

    def delete(key, &)
      super(convert_key(key), &)
    end

    def values_at(*keys)
      keys.map { |key| self[key] }
    end

    def merge(other, &)
      dup.merge!(other, &)
    end

    def merge!(other, &block)
      other.each do |key, value|
        value = yield(convert_key(key), self[key], value) if block && key?(key)
        self[key] = value
      end
      self
    end
    alias update merge!

    def dup
      self.class.deep_convert(to_h)
    end

    def slice(*keys)
      self.class.new.tap do |h|
        keys.each { |k| h[k] = self[k] if key?(k) }
      end
    end

    def except(*keys)
      dup.tap { |h| keys.each { |k| h.delete(k) } }
    end

    # YAML serialization: encode as plain Hash to avoid Psych::DisallowedClass
    # errors when using YAML.safe_load or YAML.load with restricted classes.
    #
    # Without this, YAML.dump would output:
    #   --- !ruby/hash:Onetime::IndifferentHash
    #
    # With this, it outputs:
    #   ---
    #
    # This ensures deep_clone and other YAML-based operations work transparently.
    def encode_with(coder)
      coder.represent_map(nil, self)
    end

    private

    def convert_key(key)
      key.is_a?(Symbol) ? key.to_s : key
    end
  end
end
