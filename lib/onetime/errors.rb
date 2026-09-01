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

  # Raised at boot by CheckSecretVerifier when site.secret_verifier_mode is
  # 'enforce' and the stored key verifier does not match the running SECRET
  # (C10/QS-6). Fatal even in CLI mode: every pre-rotation ciphertext is
  # unrecoverable under the wrong key, so continuing silently is the failure
  # this check exists to prevent.
  class SecretVerifierMismatch < Problem
    include FatalBootError
  end

  # Raised when a secret's ciphertext cannot be decrypted with the running
  # SECRET (C10/QS-6): either the boot-time verifier already flagged a
  # mismatch (fast-fail before any reveal claim), or this ciphertext predates
  # a key rotation (per-secret signal; the reveal claim is rolled back so the
  # record and ciphertext survive). Maps to HTTP 503 in otto_hooks — a
  # server-side condition, retryable after the operator restores the key.
  class SecretUndecryptable < Problem
    attr_accessor :error_key, :args
    attr_reader :code

    DEFAULT_MESSAGE = 'This secret cannot be decrypted right now. The link is ' \
                      'still intact — the site operator must restore the ' \
                      'encryption key before it can be revealed.'

    def initialize(message = DEFAULT_MESSAGE, code: 'secret_undecryptable',
                   error_key: 'api.secrets.errors.secret_undecryptable', args: {})
      super(message)
      @code      = code
      @error_key = error_key
      @args      = args
    end

    def to_h
      {
        error: message,
        error_type: 'SecretUndecryptable',
        code: code,
        error_key: error_key,
      }.compact
    end
  end

  # An authentication gate could not READ the policy for the request host
  # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference /
  # #degradation-is-fail-closed,
  # ADR-024#operator-defaults-require-positive-classification, #4139/#4157): the
  # per-domain half of that policy lives in the datastore, so a read failure
  # leaves the gate unable to say what this host permits. Sign-in and sign-up
  # each get a subclass; the SHAPE lives here exactly once, because the two
  # must not drift into differently-formed 503s for the identical failure.
  #
  # Maps to HTTP 503 at every edge — otto_hooks (Core, invite API) and
  # Auth::ErrorTranslator (the Roda auth router) — because that is the piece
  # that makes unconditional fail-closed survivable. A gate's normal reject
  # shape is a 404 (ADR-034#reject-as-not-found-not-forbidden) whose whole
  # point is to be indistinguishable from an
  # undefined route, or a bare redirect home; answering an unreadable policy
  # the same way would put mystery not-founds on the auth routes of an install
  # that restricts nothing, indistinguishable from a routing regression. A 503
  # says what actually happened — a backend read failed, retry — and is
  # alertable as itself. That 404 exists to hide policy-gated methods; when the
  # policy is unreadable there is no policy to hide.
  #
  # NOT a FormError/Forbidden: nothing about the request is wrong.
  #
  # Otto resolves error handlers by EXACT class name (Otto::Core::ErrorHandler
  # looks up `error.class.name`), so every subclass needs its own
  # register_error_handler entry in lib/onetime/application/otto_hooks.rb —
  # inheriting from this class is not enough to inherit the 503.
  class AuthPolicyUnavailable < Problem
    # Seconds. Surfaced in the body (Otto error handlers cannot set response
    # headers) and lifted into a Retry-After header by
    # Onetime::Middleware::RetryAfterHeader.
    RETRY_AFTER = 5

    def initialize(message = self.class::DEFAULT_MESSAGE)
      super
    end

    # error_type is derived from the class name rather than restated per
    # subclass: the two surfaces must be separable in alerting (a 503 on
    # sign-up is a different page being down than a 503 on sign-in) without
    # anyone having to keep a hand-written string in sync with the class.
    def to_h
      {
        error: message,
        error_type: self.class.name.split('::').last,
        retry_after: self.class::RETRY_AFTER,
      }
    end
  end

  # The `restrict_to` / sign-in policy for the REQUEST HOST could not be read.
  # Raised by Core::Controllers::Base#signin_policy_read_failed! and by
  # SigninConfig.resolve_lookup_failure.
  class SigninPolicyUnavailable < AuthPolicyUnavailable
    DEFAULT_MESSAGE = 'Sign-in is temporarily unavailable. Please try again shortly.'
  end

  # The sign-up policy for the REQUEST HOST could not be read (#4157). Same
  # rule and same shape as the sign-in sibling above, deliberately NOT the same
  # class: the user-visible copy would otherwise say "sign-in" on a failed
  # POST /auth/create-account, and the error_type is what routes the alert.
  #
  # The decision to raise is not restated here or at the call sites — it is
  # SignupConfig.resolve_lookup_failure, which carves out positively-classified
  # operator hosts via the same SigninConfig.operator_host? predicate the
  # sign-in path uses, so the two gates cannot disagree about which hosts
  # survive a datastore blip.
  class SignupPolicyUnavailable < AuthPolicyUnavailable
    DEFAULT_MESSAGE = 'Sign-up is temporarily unavailable. Please try again shortly.'
  end

  # Raised by Organization.create! when the contact_email unique index already
  # holds a reservation for that address (the HSETNX check-and-reserve lost).
  # Rescue this class, never match on the message: the call sites that carry a
  # fallback (retry without a contact_email, adopt the orphaned org, render
  # :email_taken) must not be silently disabled by a reworded message.
  class OrganizationExists < Problem
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

  # =========================================================================
  # CRITICAL ARCHITECTURAL WARNING: EXCEPTION HANDLER ORDERING
  # =========================================================================
  #
  # Onetime::Forbidden represents a standard access-control error (ADR-013).
  # It inherits from RuntimeError (which is a subclass of StandardError).
  #
  # Because of this class hierarchy, in any controller action or middleware
  # that uses a catch-all rescue block (`rescue StandardError => ex`),
  # Onetime::Forbidden WILL be caught by that block if not handled first.
  #
  # To prevent access control errors from being swallowed, logged as system
  # failures, and downgraded to 500 Internal Server Errors, you MUST rescue
  # Onetime::Forbidden explicitly BEFORE StandardError and re-raise it:
  #
  #   rescue Onetime::Forbidden
  #     raise # Propagate up to OttoHooks Forbidden 403 handler
  #   rescue StandardError => ex
  #     # Handle unexpected 500 system errors here
  #   end
  #
  # =========================================================================
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

  # Raised when a destructive colonel verb was invoked without the matching
  # server-side confirmation token (#4326). A Forbidden subclass deliberately:
  # AuditedFailure.authorization_rejection? drops the whole Forbidden family, so a
  # compromised colonel session cannot mint audit events by hammering a destructive
  # route (the operator trail is count-capped with NO TTL).
  class ConfirmationRequired < Forbidden
    ERROR_CODE = 'confirmation_required'

    attr_reader :field

    def initialize(message = 'Confirmation required', field: nil, error_key: nil, args: {})
      super(message, error_key: error_key, args: args)
      @field = field
    end

    def to_h
      {
        error: message,
        error_type: 'ConfirmationRequired',
        error_code: ERROR_CODE,
        field: field,
        error_key: error_key,
      }.compact
    end
  end

  # Raised when a TIER 1 colonel verb is invoked outside a live step-up window
  # (#4327). Forbidden subclass for the same audit-exclusion reason as
  # {ConfirmationRequired}: whoever holds the cookie can drive this rejection on
  # demand, and the operator trail is count-capped with no TTL.
  #
  # `window` is the configured elevation lifetime in seconds, so the console can
  # tell the operator how long a fresh window will last before they re-enter a
  # credential.
  class ElevationRequired < Forbidden
    ERROR_CODE = 'elevation_required'

    attr_reader :window

    def initialize(message = 'Step-up authentication required', window: nil, error_key: nil, args: {})
      super(message, error_key: error_key, args: args)
      @window = window
    end

    def to_h
      {
        error: message,
        error_type: 'ElevationRequired',
        error_code: ERROR_CODE,
        window: window,
        error_key: error_key,
      }.compact
    end
  end

  # Raised when a step-up ATTEMPT itself fails (#4327) — a wrong password, or a
  # factor this account cannot satisfy. Distinct from {ElevationRequired}, which
  # says "you never elevated": this one says "the elevation you just tried did
  # not work", and the console renders the server's remediation message.
  class ElevationFailed < Forbidden
    ERROR_CODE = 'elevation_failed'

    attr_reader :factor

    def initialize(message = 'Step-up authentication failed', factor: nil, error_key: nil, args: {})
      super(message, error_key: error_key, args: args)
      @factor = factor
    end

    def to_h
      {
        error: message,
        error_type: 'ElevationFailed',
        error_code: ERROR_CODE,
        factor: factor,
        error_key: error_key,
      }.compact
    end
  end

  # A destructive-action guard was called with no expected token — a programming
  # error in the calling logic class, never a caller-triggerable condition. 500,
  # never a silent admit. Distinct from a bare Onetime::Problem because Otto
  # resolves error handlers by EXACT class name and Problem is not registered.
  class GuardMisconfigured < Problem
    ERROR_CODE = 'guard_misconfigured'

    def to_h
      {
        error: 'Internal configuration error',
        error_type: 'GuardMisconfigured',
        error_code: ERROR_CODE,
      }
    end
  end
end
