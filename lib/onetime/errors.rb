# lib/onetime/errors.rb
#
# frozen_string_literal: true

module Onetime
  # Marker module for boot errors that must always halt execution, even in
  # CLI mode. Without this marker, boot! swallows OT::Problem in :cli to
  # allow REPL debugging — but config errors leave OT.conf unusable, so
  # commands hit nil errors downstream. Including this module signals
  # "boot cannot recover from this; surface the error to the user."
  module FatalBootError; end

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

    # Exception#to_s returns the message stored at construction time inside
    # the C-level internal slot, which never changes — so when ErrorResolver
    # mutates @message via the accessor to install the localized string,
    # to_s would still return the original. That breaks loggers and
    # middleware that rely on the standard exception string representation.
    # Delegating to @message keeps to_s consistent with #message.
    def to_s
      @message || super
    end
  end

  # Raised when there is an issue with configuration settings, such as missing,
  # invalid, or malformed configuration data during initialization. This
  # exception indicates that the application's configuration is not set up
  # correctly and needs to be reviewed and corrected before normal operation
  # can proceed.
  class ConfigError < Problem
    include FatalBootError
  end

  class MigrationError < Problem
    include FatalBootError
  end

  class RecordNotFound < Problem
    # i18n shape: error_key + args are resolved at the HTTP edge so logic
    # classes never touch I18n. error_key is the full dotted i18n key (e.g.
    # 'api.organizations.errors.organization_not_found'), keeping each call
    # site greppable from the JSON locale entry.
    attr_accessor :error_key, :args

    def initialize(message = nil, error_key: nil, args: {})
      super(message)
      @error_key = error_key
      @args      = args
    end

    def to_h
      {
        error: message,
        error_type: 'RecordNotFound',
        error_key: error_key,
      }.compact
    end
  end

  class MissingSecret < RecordNotFound
  end

  class FormError < Problem
    attr_accessor :form_fields, :field, :error_type, :error_key, :args

    # Two shapes:
    # - Legacy: FormError.new('resolved string', field:, error_type:)
    # - i18n:   FormError.new(error_key: 'api.organizations.errors.email_required',
    #                         args: { max: 5 }, field:, error_type:)
    # The edge handler resolves error_key+args via I18n.t; logic never does.
    def initialize(message = nil, error_key: nil, args: {}, field: nil, error_type: nil)
      super(message)
      @error_key  = error_key
      @args       = args
      @field      = field
      @error_type = error_type
    end

    def to_h
      {
        error: message,
        error_type: error_type,
        field: field,
        error_key: error_key,
      }.compact
    end
  end

  class Unauthorized < RuntimeError
  end

  class Forbidden < RuntimeError
    attr_accessor :message, :error_key, :args

    def initialize(message = 'Forbidden', error_key: nil, args: {})
      super(message)
      @message   = message
      @error_key = error_key
      @args      = args
    end

    # See Problem#to_s — same divergence applies to every Forbidden
    # subclass since they all reuse this attr_accessor :message.
    def to_s
      @message || super
    end

    def to_h
      {
        error: message,
        error_type: 'Forbidden',
        error_key: error_key,
      }.compact
    end
  end

  # Raised when a user lacks the required entitlement for an action.
  # Contains upgrade path information for the API response.
  #
  # i18n shape: error_key + args inherited from Forbidden are resolved at
  # the HTTP edge by Onetime::Application::ErrorResolver, so logic code
  # passes the dotted i18n key (e.g. 'api.entitlements.errors.api_access_required')
  # and never touches I18n directly.
  class EntitlementRequired < Forbidden
    attr_reader :entitlement, :current_plan, :upgrade_to

    def initialize(entitlement, current_plan: nil, upgrade_to: nil, message: nil,
                   error_key: nil, args: {})
      @entitlement    = entitlement
      @current_plan   = current_plan
      @upgrade_to     = upgrade_to
      default_message = "Feature requires #{entitlement.to_s.tr('_', ' ')} entitlement"
      super(message || default_message, error_key: error_key, args: args)
    end

    def to_h
      {
        error: message,
        error_type: 'EntitlementRequired',
        entitlement: entitlement,
        current_plan: current_plan,
        upgrade_to: upgrade_to,
        error_key: error_key,
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
  #
  # i18n shape: error_key + args inherited from Forbidden are resolved at
  # the HTTP edge by Onetime::Application::ErrorResolver, so logic code
  # passes the dotted i18n key and never touches I18n directly.
  class GuestRoutesDisabled < Forbidden
    attr_reader :code

    def initialize(message = 'Guest API access is disabled', code: 'GUEST_ROUTES_DISABLED',
                   error_key: nil, args: {})
      super(message, error_key: error_key, args: args)
      @code = code
    end

    def to_h
      {
        error: message,
        error_type: 'GuestRoutesDisabled',
        code: code,
        error_key: error_key,
      }.compact
    end
  end

  # Raised when a rate limit is exceeded (too many failed attempts, etc.)
  # Used for security features like passphrase attempt limiting.
  #
  # i18n shape: error_key + args inherited from Forbidden are resolved at
  # the HTTP edge by Onetime::Application::ErrorResolver, so logic code
  # passes the dotted i18n key and never touches I18n directly.
  class LimitExceeded < Forbidden
    attr_reader :retry_after, :attempts, :max_attempts

    def initialize(message = 'Rate limit exceeded', retry_after: nil, attempts: nil, max_attempts: nil,
                   error_key: nil, args: {})
      super(message, error_key: error_key, args: args)
      @retry_after  = retry_after
      @attempts     = attempts
      @max_attempts = max_attempts
    end

    def to_h
      {
        error: message,
        error_type: 'LimitExceeded',
        retry_after: retry_after,
        attempts: attempts,
        max_attempts: max_attempts,
        error_key: error_key,
      }.compact
    end
  end
end
