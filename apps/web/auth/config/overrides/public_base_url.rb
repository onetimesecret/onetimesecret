# apps/web/auth/config/overrides/public_base_url.rb
#
# frozen_string_literal: true

require_relative '../../lib/public_host'

module Auth::Config::Overrides
  # Rodauth credential links and their branding use the recipient account's
  # authorized tenant origin, or a configured canonical origin. A verified
  # custom domain is insufficient without active membership authorizing that
  # exact domain. SSO and WebAuthn keep their browser-origin resolvers.
  #
  # Nonmember tenant requests receive canonical links, including ordinary
  # password signups: their personal workspace is not membership in the tenant
  # organization. This resolver does not check destination route availability
  # or widen its policy. Global sign-in flags gate tenants too; disabling them
  # does not create a tenant-only password/email deployment.
  module PublicBaseUrl
    module ResetPasswordOrigin
      # Also protect direct/internal key creation, before INSERT or updating an
      # existing key's email_last_sent; an email-time failure alone is too late.
      #
      # On the public request route the refusal depends on the recipient
      # (membership), so it answers with the generic response used for missing,
      # unopen and throttled accounts (LoginRequestEnumeration). A 500 here
      # would tell an unauthenticated caller the login names an open account.
      # Halts before the key write; direct/internal callers still get the raise.
      def create_reset_password_key
        begin
          base_url
        rescue Auth::PublicHost::MissingAllowlistedOrigin
          raise unless current_route == :reset_password_request

          Auth::Logging.log_auth_event(
            :reset_password_request_no_credential_origin,
            level: :error,
            account_id: account_id,
          )
          reset_password_email_sent_response
        end
        super
      end
    end

    # The same guard for the magic-link request (RISK-2026-08-14-M03).
    # create_email_auth_key is the first write in Rodauth 2.45.0's
    # _email_auth_request: it deletes the account's expired key row, then
    # either updates email_last_sent or inserts a key. On POST
    # /auth/email-login-request a recipient with no credential origin answers
    # like a missing account (LoginRequestEnumeration), not with a 500 that
    # only an open account can produce. Direct/internal callers still raise.
    module EmailAuthOrigin
      def create_email_auth_key
        begin
          base_url
        rescue Auth::PublicHost::MissingAllowlistedOrigin
          raise unless current_route == :email_auth_request

          Auth::Logging.log_auth_event(
            :email_auth_request_no_credential_origin,
            level: :error,
            account_id: account_id,
          )
          email_auth_email_sent_response
        end
        super
      end
    end

    # The same guard for POST /auth/verify-account-resend. The check runs
    # first in verify_account_email_resend, before Rodauth reads the key and
    # updates email_last_sent, so a refused resend writes nothing. An
    # unverified account with no key row also answers success on this route,
    # so checking before the key read changes no answer. Internal requests
    # (ResendVerifyAccount) still raise.
    module VerifyAccountOrigin
      def verify_account_email_resend
        begin
          base_url
        rescue Auth::PublicHost::MissingAllowlistedOrigin
          raise unless current_route == :verify_account_resend

          Auth::Logging.log_auth_event(
            :verify_account_resend_no_credential_origin,
            level: :error,
            account_id: account_id,
          )
          verify_account_email_sent_response
        end
        super
      end
    end

    # One recipient-origin guard per credential-mailing request route, keyed
    # by the feature that defines the guarded method.
    RECIPIENT_ORIGIN_GUARDS = {
      reset_password: ResetPasswordOrigin,
      email_auth: EmailAuthOrigin,
      verify_account: VerifyAccountOrigin,
    }.freeze

    def self.configure(auth)
      auth.base_url do
        Auth::PublicHost.required_credential_base_url!(request.env, account)
      end

      # rubocop:disable-next Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # Brand credential emails with the same recipient-bound origin.
        def public_display_domain
          Auth::PublicHost.credential_display_host(request.env, account)
        end
      end
    end

    # Prepend the guard of every enabled feature in RECIPIENT_ORIGIN_GUARDS.
    #
    # Separate from .configure because it reads the features enabled SO FAR,
    # and :email_auth and :verify_account (the latter also transitively via
    # webauthn_verify_account) are enabled after .configure runs; config.rb
    # calls this after every feature block. A prepended module runs before the
    # class's own definitions whatever the include order, so these chain with
    # LoginRequestEnumeration's class-level verify_account_email_resend
    # (guard first, then that override, then Rodauth) rather than replace it.
    def self.configure_recipient_origins(auth)
      auth_class = auth.instance_variable_get(:@auth)
      features   = auth_class&.features || []

      RECIPIENT_ORIGIN_GUARDS.each do |feature, guard|
        next unless features.include?(feature)

        auth.auth_class_eval { prepend guard }
      end
    end
  end
end
