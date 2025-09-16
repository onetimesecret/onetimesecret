require_relative 'utils/enumerables'
require_relative 'utils/sanitation'
require_relative 'utils/strings'
require_relative 'utils/time_utils'

module Onetime
  module Utils
    extend Enumerables
    extend Sanitation
    extend Strings
    extend TimeUtils

    class << self
      attr_accessor :fortunes

      # NOTE: Temporary until Familia 2-pre11
      # @see #shorten_securely for truncation details
      def generate_short_id
        hexstr = SecureRandom.hex(32) # generate with all 256 bits
        shorten_securely(hexstr, bits: 64) # and then shorten
      end

    # Generate a configurable password based on character set options
    def generate_password(length = 12, options = {})
      # Default options from configuration or fallback values
      opts = {
        uppercase: true,
        lowercase: true,
        numbers: true,
        symbols: false,
        exclude_ambiguous: true,
      }.merge(options)

      # Build character set based on options
      chars = []
      chars.concat(('A'..'Z').to_a) if opts[:uppercase]
      chars.concat(('a'..'z').to_a) if opts[:lowercase]
      chars.concat(('0'..'9').to_a) if opts[:numbers]
      if opts[:symbols]
        chars.concat(%w[! @ # $ % ^ & * ( ) _ - + = [ ] { } | \\ : ; " ' < > , . ? / ~ `])
      end

      # Remove ambiguous characters if requested
      if opts[:exclude_ambiguous]
        chars.delete_if { |char| %w[0 O o l 1 I i].include?(char) }
      end

      # Ensure we have at least some characters to work with
      if chars.empty?
        chars = VALID_CHARS_SAFE # Fallback to safe default
      end

      # Generate password
      (1..length).map { chars[rand(chars.length)] }.join
    end

    def indifferent_params(params)
      if params.is_a?(Hash)
        params = indifferent_hash.merge(params)
        params.each do |key, value|
          next unless value.is_a?(Hash) || value.is_a?(Array)

      # Returns a random fortune from the configured fortunes array.
      # Provides graceful degradation with fallback messages when fortunes
      # are unavailable or malformed, ensuring the application never fails
      # due to fortune retrieval issues.
      #
      # @return [String] A random fortune string, or a fallback message
      # @raise [OT::Problem] Never raised - all errors are caught and logged
      #
      # @example Normal usage
      #   Utils.fortunes = ["Good luck!", "Fortune favors the bold"]
      #   Utils.random_fortune # => "Good luck!" or "Fortune favors the bold"
      #
      # @example Graceful degradation
      #   Utils.fortunes = nil
      #   Utils.random_fortune # => "Unexpected outcomes bring valuable lessons."
      #
      # @note All errors are logged but never propagated to maintain system stability
      # @security Validates input type to prevent injection of malicious objects
      def random_fortune
        raise OT::Problem, 'No fortunes' if fortunes.nil?
        raise OT::Problem, "#{fortunes.class} is not an Array" unless fortunes.is_a?(Array)

        fortune = fortunes.sample.to_s.strip
        raise OT::Problem, 'No fortune found' if fortune.empty?

        fortune
      rescue OT::Problem => ex
        OT.le "#{ex.message}"
        'Unexpected outcomes bring valuable lessons.'
      rescue StandardError => ex
        OT.le "#{ex.message} (#{fortunes.class})"
        OT.ld "#{ex.backtrace.join("\n")}"
        'A house is full of games and puzzles.'
      end

      # Converts an absolute file path to a path relative to the application's
      # base directory. This simplifies logging and error reporting by showing
      # only the relevant parts of file paths instead of lengthy absolute paths.
      #
      # @param file [String, Pathname] The absolute file path to convert
      # @return [Pathname] A relative path from application's base directory
      #
      # @example Using application base directory
      #   # When ONETIME_HOME is set to "/app/onetime"
      #   Utils.pretty_path("/app/onetime/lib/models/user.rb") # => "lib/models/user.rb"
      #
      # @example Using current directory as fallback
      #   # When ONETIME_HOME is not set and __dir__ is "/home/dev/project/lib"
      #   Utils.pretty_path("/home/dev/project/lib/config.rb") # => "config.rb"
      #
      # @note The method respects the ONETIME_HOME environment variable as the
      #   base path, falling back to the current directory if not set
      # @see Pathname#relative_path_from Ruby standard library documentation
      def pretty_path(filepath)
        return nil if filepath.nil?

        basepath    = ENV.fetch('ONETIME_HOME', __dir__)
        Pathname.new(filepath).relative_path_from(basepath)
      end
    end
  end
end
