# lib/onetime/errors.rb
#
# frozen_string_literal: true

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
      @field      = field
      @error_type = error_type
    end

    def to_h
      {
        error: error_type || 'FormError',
        message: message,
        field: field,
      }.compact
    end
  end

  class Unauthorized < RuntimeError
  end

  class Forbidden < RuntimeError
    attr_reader :message

    def initialize(message = 'Forbidden')
      super
      @message = message
    end
  end

  # Raised when a user lacks the required entitlement for an action.
  # Contains upgrade path information for the API response.
  class EntitlementRequired < Forbidden
    attr_reader :entitlement, :current_plan, :upgrade_to

    def initialize(entitlement, current_plan: nil, upgrade_to: nil, message: nil)
      @entitlement  = entitlement
      @current_plan = current_plan
      @upgrade_to   = upgrade_to
      super(message || "Feature requires #{entitlement.to_s.tr('_', ' ')} entitlement")
    end

    def to_h
      {
        error: message,
        entitlement: entitlement,
        current_plan: current_plan,
        upgrade_to: upgrade_to,
      }.compact
    end
  end

  class Redirect < RuntimeError
    attr_reader :location, :status

    def initialize(l, s = 302)
      @location = l
      @status   = s
    end
  end

  # Raised when guest API routes are disabled or a specific guest operation is disabled.
  # Contains an error code for the API response.
  class GuestRoutesDisabled < Forbidden
    attr_reader :code

    def initialize(message = 'Guest API access is disabled', code: 'GUEST_ROUTES_DISABLED')
      super(message)
      @code = code
    end

    def to_h
      {
        message: message,
        code: code,
      }
    end
  end
end
