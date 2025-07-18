
require_relative 'utils/enumerables'
require_relative 'utils/numbers'
require_relative 'utils/sanitation'
require_relative 'utils/strings'
require_relative 'utils/time_utils'

module Onetime
  module Utils
    extend Sanitation
    extend TimeUtils
    extend Numbers
    extend Strings
    extend Enumerables

    class << self
      attr_accessor :fortunes

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
