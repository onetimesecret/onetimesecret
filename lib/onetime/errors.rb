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

  class MigrationError < Problem
  end

  class RecordNotFound < Problem
  end

  class MissingSecret < RecordNotFound
  end

  class FormError < Problem
    attr_accessor :form_fields, :field, :error_type

    def initialize(message = nil, field: nil, error_type: nil)
      super(message)
      @field = field
      @error_type = error_type
    end
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
      got_display = got.size <= 16 ? got : got[0, 16] + '...'
      wanted_display = wanted.size <= 16 ? wanted : wanted[0, 16] + '...'
      "BAD SHRIMP FOR #{@path}: #{@user}: #{got_display}/#{wanted_display}"
    end

    def message
      'Sorry, bad shrimp'
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
