# tests/unit/ruby/try/test_helpers.rb

# Establish the environment
ENV['RACK_ENV'] ||= 'production'
ENV['ONETIME_HOME'] ||= File.expand_path('../../../../..', __FILE__).freeze

Warning[:deprecated] = true if ['development', 'dev', 'test'].include?(ENV['RACK_ENV'])

project_root = ENV['ONETIME_HOME']
app_root = File.join(project_root, '/apps').freeze

$LOAD_PATH.unshift(File.join(app_root, 'api'))
$LOAD_PATH.unshift(File.join(app_root, 'web'))

# This tells OT::Configurator#load_with_impunity! to look in the preset list
# of paths to look for a config file and find one that matches this basename.
# See ./tests/unit/ruby/rspec/onetime/configurator_spec.rb
ENV['ONETIME_CONFIG_FILE_BASENAME'] = 'config.test'

require 'onetime'

global_secret = OT.conf.dig('site', 'secret') || nil
OT.li("[TRY] Setting global secret: #{global_secret}")
Gibbler.secret = global_secret.freeze unless Gibbler.secret

class IndifferentHash
  # Initializes a new IndifferentHash.
  #
  # @param hash [Hash] The initial hash to store.
  def initialize(hash = {})
    @hash = hash.transform_keys(&:to_sym)
  end

  # Retrieves the value associated with the given key.
  #
  # @param key [String, Symbol] The key to look up.
  # @return [Object] The value associated with the key.
  def [](key)
    @hash[key.to_sym]
  end

  # Sets the value for the given key.
  #
  # @param key [String, Symbol] The key to set.
  # @param value [Object] The value to associate with the key.
  def []=(key, value)
    @hash[key.to_sym] = value
  end

  # Handles method calls to access or set values.
  #
  # @param method_name [Symbol] The name of the method called.
  # @param args [Array] The arguments passed to the method.
  # @param block [Proc] An optional block.
  # @return [Object] The value associated with the key, or nil if setting a value.
  def method_missing(method_name, *args, &block)
    if method_name.to_s.end_with?('=')
      self[method_name.to_s.chomp('=')] = args.first
    else
      self[method_name]
    end
  end

  # Checks if the object responds to a given method.
  #
  # @param method_name [Symbol] The name of the method.
  # @param include_private [Boolean] Whether to include private methods.
  # @return [Boolean] True if the object responds to the method, false otherwise.
  def respond_to_missing?(method_name, include_private = false)
    @hash.key?(method_name.to_sym) || super
  end
end
