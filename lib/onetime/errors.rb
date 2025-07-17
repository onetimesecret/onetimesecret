require 'json'

module Onetime
  # The Problem class inherits from RuntimeError, which is a subclass of StandardError.
  # Both RuntimeError and StandardError are standard exception classes in Ruby, but
  # RuntimeError is used for errors that are typically caused by the program's logic
  # and are usually rescued implicitly (e.g., in `rescue RuntimeError`).
  # StandardError is the default exception type for many Ruby errors and is also rescue-able.
  #
  # Subclassing from RuntimeError indicates the error is more specific to runtime conditions.
  class Problem < RuntimeError
    attr_accessor :message

    def initialize(message = nil)
      super
      @message = message
    end
  end

  # Raised when there is an issue with configuration settings, such as missing,
  # invalid, or malformed configuration data during initialization. This
  # exception indicates that the application's configuration is not set up
  # correctly and needs to be reviewed and corrected before normal operation
  # can proceed.
  class ConfigError < Problem
  end

  # Specific error for schema validation failures with structured information
  # about which paths in the configuration are problematic
  class ConfigValidationError < ConfigError
    attr_reader :messages, :paths

    def initialize(messages:, paths: nil)
      @messages = Array(messages).compact.reject(&:empty?)
      @paths    = paths
      super(formatted_message)
    end

    private

    def formatted_message
      return 'Configuration validation failed' if @messages.empty?

      parts = [
        'Configuration validation failed:',
        *@messages.each_with_index.map { |msg, i| "  #{i + 1}. #{msg}" },
      ]

      if @paths&.any?
        parts << ''
        parts << 'Affected paths:'
        parts << JSON.pretty_generate(OT::Utils.type_structure(@paths))
          .lines
          .map { |line| "  #{line}" }
          .join
          .chomp
      end

      parts.join("\n")
    end
  end

  class RecordNotFound < Problem
  end

  class MissingSecret < RecordNotFound
  end

  class FormError < Problem
    attr_accessor :form_fields
  end

  class BadShrimp < Problem
    attr_reader :path, :user, :got, :wanted

    def initialize(path, user, got, wanted)
      @path   = path
      @user   = user
      @got    = got.to_s
      @wanted = wanted.to_s
    end

    def report
      "BAD SHRIMP FOR #{@path}: #{@user}: #{got.shorten(16)}/#{wanted.shorten(16)}"
    end

    def message
      'Sorry, bad shrimp'
    end
  end

  class LimitExceeded < RuntimeError
    attr_accessor :event, :message, :cust
    attr_reader :identifier, :event, :count

    def initialize(identifier, event, count)
      @identifier = identifier
      @event      = event
      @count      = count
    end

    def message
      "[limit-exceeded] #{identifier} for #{event} (#{count})"
    end
  end

  class Unauthorized < RuntimeError
  end

  class Redirect < RuntimeError
    attr_reader :location, :status

    def initialize(l, s = 302)
      @location = l
      @status   = s
    end
  end
end
