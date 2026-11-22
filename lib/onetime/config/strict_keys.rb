# lib/onetime/config/strict_keys.rb
#
# frozen_string_literal: true

module Onetime
  module Config
    # Raised by a StrictKeys Hash when it is read or written with a key that
    # is not a String.
    #
    # A TypeError, as Hash#dig raises for a value it cannot dig into, and not
    # an Onetime::Problem (see MissingPathError).
    class KeyTypeError < TypeError
      # @return [Object] the key as given
      attr_reader :key

      # @param key [Object] the key that is not a String
      def initialize(key)
        @key = key
        super("Config key #{key.inspect} is a #{key.class}; config keys are Strings")
      end
    end

    # A key check for the Hashes in the config tree, for the test suites.
    #
    # Config keys are Strings on every load path (Onetime::Config.string_keys),
    # so a section read with a Symbol, `OT.conf.get('site.admin', {})[:enabled]`,
    # reads nil without an error. OT.conf.get takes String segments only and
    # cannot see that read. A Hash with StrictKeys raises KeyTypeError instead,
    # on a non-String key given to #[], #[]=, #store, #dig, #fetch, #key?,
    # #has_key?, #include? or #member?. A String key reads and writes as on a
    # plain Hash.
    #
    # Onetime::Config.wrap gives it to every Hash in the tree when
    # Onetime::Config.strict_keys? is true, which the test helpers set
    # (spec/spec_helper.rb, try/support/test_helpers.rb). It is off otherwise,
    # and the config Hashes are plain Hashes.
    #
    # #dig checks its first key only. Hash#dig reads that key without calling
    # #[], and passes the rest to the value's #dig only when the value
    # overrides it, as a nested StrictKeys Hash does; that Hash checks its own
    # key. Other Hash methods (values_at, slice, merge!, ...) are not checked.
    # A Hash written into the tree with #[]= or #store is given StrictKeys,
    # with the Hashes below it.
    module StrictKeys
      # The Hash#store of a plain Hash: installs a value without the key
      # check, as the key may not be a String in a Hash a test wrote.
      HASH_STORE = Hash.instance_method(:store)
      private_constant :HASH_STORE

      def [](key)
        StrictKeys.check!(key)
        super
      end

      def []=(key, value)
        StrictKeys.check!(key)
        super(key, StrictKeys.install(value))
      end

      def store(key, value)
        StrictKeys.check!(key)
        super(key, StrictKeys.install(value))
      end

      def dig(key, *)
        StrictKeys.check!(key)
        super
      end

      def fetch(key, *, &)
        StrictKeys.check!(key)
        super
      end

      def key?(key)
        StrictKeys.check!(key)
        super
      end

      def has_key?(key) # rubocop:disable Naming/PredicatePrefix -- Hash's own name
        StrictKeys.check!(key)
        super
      end

      def include?(key)
        StrictKeys.check!(key)
        super
      end

      def member?(key)
        StrictKeys.check!(key)
        super
      end

      # @param key [Object]
      # @raise [KeyTypeError] unless key is a String
      def self.check!(key)
        raise KeyTypeError.new(key) unless key.is_a?(String)
      end

      # Gives StrictKeys to +node+, when it is a Hash, and to every Hash below
      # it, through Hashes and Arrays. A Hash that already has it is returned
      # as it is. A frozen Hash or Array cannot be changed, so it is replaced
      # by a frozen copy (shallow, as Onetime::Config.wrap copies a frozen
      # root): the caller stores the return value.
      #
      # @param node [Object]
      # @return [Object] node, or its copy
      def self.install(node)
        return node if node.is_a?(StrictKeys)

        case node
        when Hash
          copy = node.frozen? ? node.dup : node
          copy.extend(StrictKeys)
          copy.each_pair do |key, value|
            strict = install(value)
            HASH_STORE.bind_call(copy, key, strict) unless strict.equal?(value)
          end
          node.frozen? ? copy.freeze : copy
        when Array
          install_array(node)
        else
          node
        end
      end

      def self.install_array(array)
        strict = array.map { |item| install(item) }
        return array if strict.each_with_index.all? { |item, index| item.equal?(array[index]) }
        return strict.freeze if array.frozen?

        array.replace(strict)
      end
      private_class_method :install_array
    end
  end
end
