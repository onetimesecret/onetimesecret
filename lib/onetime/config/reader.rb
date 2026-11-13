# lib/onetime/config/reader.rb
#
# frozen_string_literal: true

require_relative '../errors'

module Onetime
  module Config
    # Raised by OT.conf.get when the path is not set and no default was given.
    class MissingPathError < Onetime::ConfigError
      # @return [Array<String>] the requested path
      attr_reader :path

      # @param path [Array<String>] the requested path
      # @param index [Integer] the first segment that could not be read
      # @param nil_parent [Boolean] the section holding that segment is nil
      #   rather than missing the key
      def initialize(path, index, nil_parent: false)
        @path  = path
        label  = Reader.label(path)
        reason = if nil_parent
          "'#{Reader.label(path[0, index])}' is nil"
        elsif index.zero?
          "there is no top-level '#{path[0]}'"
        else
          "'#{Reader.label(path[0, index])}' has no '#{path[index]}'"
        end
        super("Config path '#{label}' is not set: #{reason}")
      end
    end

    # Raised by OT.conf.get when the path runs through a value that is not a
    # section (Hash). Raised whether or not a default was given: the config
    # tree does not have the shape the caller expects.
    class PathTypeError < Onetime::ConfigError
      # @return [Array<String>] the requested path
      attr_reader :path

      # @param path [Array<String>] the requested path
      # @param index [Integer] the segment that was to be read from the value
      # @param value [Object] the value found at path[0, index]
      def initialize(path, index, value)
        @path = path
        super(
          "Config path '#{Reader.label(path)}' cannot be read: " \
          "'#{Reader.label(path[0, index])}' is #{value.class}, not a section",
        )
      end
    end

    # The dotted-path reader of OT.conf. Onetime::Config.wrap installs it on
    # the root config Hash, which stays a Hash: sections below the root are
    # plain Hashes with String keys.
    #
    #   OT.conf.get('site.host')                           # required setting
    #   OT.conf.get('site.admin.elevation', {})            # default when absent or nil
    #   OT.conf.get('site.product_name', nil)              # optional setting
    #   OT.conf.get(['features', type, 'enabled'], false)  # variable segment
    #
    # The Array form also reaches keys that contain a dot.
    module Reader
      NO_DEFAULT = Object.new.freeze
      private_constant :NO_DEFAULT

      # @param path [String, Array<String>] a dotted path, or its segments
      # @param default [Object] the result when the path is absent or its
      #   value is nil. Without one, an absent path raises. Positional only:
      #   `get(path, default: false)` raises ArgumentError instead of
      #   returning the truthy Hash `{default: false}`.
      # @return [Object] the value. false and 0 are values and are returned
      #   as they are.
      # @raise [MissingPathError] the path is absent and no default was given
      # @raise [PathTypeError] the path runs through a value that is not a Hash
      # @raise [ArgumentError] the path is empty, or a segment is not a
      #   non-empty String, or a keyword argument was given
      def get(path, default = NO_DEFAULT, **nil)
        segments = Reader.segments(path)
        node     = self

        segments.each_with_index do |segment, index|
          raise PathTypeError.new(segments, index, node) unless node.is_a?(Hash)

          unless node.key?(segment)
            return default unless NO_DEFAULT.equal?(default)

            raise MissingPathError.new(segments, index)
          end

          node = node[segment]
          next unless node.nil?
          return default unless NO_DEFAULT.equal?(default)
          return nil if index == segments.length - 1

          raise MissingPathError.new(segments, index + 1, nil_parent: true)
        end

        node
      end

      # Splits and checks a path. Segments are non-empty Strings: config keys
      # are Strings on every load path (Onetime::Config.string_keys).
      #
      # @param path [String, Array<String>]
      # @return [Array<String>]
      # @raise [ArgumentError]
      def self.segments(path)
        segments = case path
        when String then path.split('.', -1)
        when Array then path
        else
          raise ArgumentError, "config path must be a String or an Array of Strings, not #{path.class}"
        end

        raise ArgumentError, 'config path is empty' if segments.empty?

        segments.each do |segment|
          next if segment.is_a?(String) && !segment.empty?

          raise ArgumentError,
            "config path #{path.inspect} has the segment #{segment.inspect}; " \
            'each segment must be a non-empty String'
        end

        segments
      end

      # 'site.admin.elevation', or the segment list when a segment holds a dot
      # (a domain-keyed map such as mail.truemail.validation_type_for).
      #
      # @param segments [Array<String>]
      # @return [String]
      def self.label(segments)
        segments.any? { |segment| segment.include?('.') } ? segments.inspect : segments.join('.')
      end
    end
  end
end
