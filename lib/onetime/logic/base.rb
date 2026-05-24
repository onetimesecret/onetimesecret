# lib/onetime/logic/base.rb
#
# frozen_string_literal: true

require 'sanitize'
require 'timeout'

require 'onetime/mail'
require 'onetime/refinements/stripe_refinements'
require 'onetime/logic/organization_context'
require 'onetime/security/input_sanitizers'
require 'onetime/application/authorization_policies'

module Onetime
  module Logic
    using Familia::Refinements::TimeLiterals

    # Base class for all logic classes across the application.
    #
    # Provides common functionality for:
    # - Session and customer context extraction
    # - Organization context management
    # - Settings processing (site, features, domains)
    # - Email validation
    # - Error handling (form errors, not found)
    # - Input sanitization (identifiers, plain text, emails)
    # - Abstract method definitions for subclasses
    #
    # This class centralizes logic that was previously in V2::Logic::Base
    # to make it available across all API versions and applications.
    class Base
      include Onetime::Logic::OrganizationContext
      include Onetime::Security::InputSanitizers
      include Onetime::Application::AuthorizationPolicies

      attr_reader :context,
        :sess,
        :cust,
        :params,
        :locale,
        :processed_params,
        :site,
        :features,
        :authentication,
        :domains_enabled,
        :strategy_result

      attr_accessor :domain_strategy, :display_domain

      def initialize(strategy_result, params, locale = nil)
        @strategy_result = strategy_result
        @params          = params

        # Extract session and user from StrategyResult
        @sess   = strategy_result.session
        @cust   = strategy_result.user
        # Use locale passed from controller (request context), fall back to params, then default
        @locale = locale || @params['locale'] || OT.default_locale

        # Log anonymous context for transition monitoring (#2733)
        if @cust.nil?
          OT.ld "[#{self.class}] Initializing with anonymous context",
            auth_method: strategy_result.auth_method
        end

        # Extract organization and team context from StrategyResult metadata
        extract_organization_context(strategy_result)

        # Extract domain context from StrategyResult metadata
        extract_domain_context(strategy_result)

        @processed_params ||= {} # TODO: Remove
        process_settings

        # Handle user model instances properly
        if @cust.is_a?(String)
          OT.li "[#{self.class}] Friendly reminder to pass in a Customer instance instead of a objid"
          @cust = Onetime::Customer.load(@cust)
        end
        # If @cust is already a Onetime::Customer instance, use it as-is

        # Won't run if params aren't passed in
        process_params if respond_to?(:process_params) && @params
      end

      def process_settings
        @site            = OT.conf.fetch('site', {})
        @features        = OT.conf.fetch('features', {})

        @authentication  = site.fetch('authentication', {})
        domains          = features.fetch('domains', {})
        @domains_enabled = domains['enabled'] || false
      end

      def valid_email?(email_value)
        loggable_email_value = OT::Utils.obscure_email(email_value)
        OT.ld "[valid_email?] Email value: #{loggable_email_value}"

        begin
          validator      = Truemail.validate(email_value)
          valid          = validator.result.valid?
          validation_str = validator.as_json
          OT.info "[valid_email?] Address is valid (#{valid}): #{validation_str}"
          valid
        rescue StandardError => ex
          OT.le "Email validation error (#{loggable_email_value}): #{ex.message}"
          OT.le ex.backtrace
          false
        end
      end

      def process
        raise NotImplementedError, 'process not implemented'
      end

      def success_data
        raise NotImplementedError, 'success_data not implemented'
      end

      protected

      def process_params
        raise NotImplementedError, 'process_params not implemented'
      end

      def form_fields
        OT.ld "No form_fields method for #{self.class} via:", caller[0..2].join("\n")
        {}
      end

      # Two call shapes (and a hybrid for callers that need both):
      # - Legacy: raise_not_found('Record not found')
      # - i18n:   raise_not_found(error_key: 'api.organizations.errors.organization_not_found',
      #                           args: { extid: '...' })
      # - Hybrid: raise_not_found('Record not found', error_key: '...', args: {...})
      #   Pre-populates the English fallback while still letting the edge
      #   localize per request locale. Useful for helpers shared with code
      #   paths that don't pass through the resolver.
      # error_key is the full dotted i18n key so each call site is greppable
      # from the JSON locale entry.
      def raise_not_found(msg = nil, error_key: nil, args: {})
        ex = Onetime::RecordNotFound.new(msg, error_key: error_key, args: args)
        raise ex
      end

      # Two call shapes (and a hybrid for callers that need both):
      # - Legacy: raise_form_error('Invalid email', field: :email)
      # - i18n:   raise_form_error(error_key: 'api.organizations.invitations.errors.email_required',
      #                            args: { max: 5 }, field: :email)
      # - Hybrid: raise_form_error('Authentication required', error_key: '...', field: :foo)
      # error_key is the full dotted i18n key. The HTTP edge resolves it per
      # request locale; logic stays free of locale/I18n boot concerns.
      def raise_form_error(msg = nil, error_key: nil, args: {}, field: nil, error_type: nil)
        ex = OT::FormError.new(msg, error_key: error_key, args: args,
                                    field: field, error_type: error_type)
        ex.form_fields = form_fields if respond_to?(:form_fields)
        raise ex
      end

      # Require that the organization has a specific entitlement.
      # Raises EntitlementRequired with upgrade path if check fails.
      #
      # For anonymous users (noauth routes), entitlement checks are skipped.
      # Guest route gating (GuestRouteGating concern) handles access control
      # for anonymous requests separately.
      #
      # @param entitlement [String, Symbol] The entitlement to check
      # @raise [Onetime::EntitlementRequired] If org lacks the entitlement
      # @return [true] If entitlement check passes
      def require_entitlement!(entitlement)
        entitlement = entitlement.to_s

        # Anonymous users don't have org context by design (NoAuthStrategy
        # returns {} for org_context). Guest route gating handles access
        # control for anonymous requests, so we skip entitlement checks here.
        # nil cust indicates anonymous (no Customer.anonymous singleton).
        return true if anonymous_user?

        # Fail-closed: auth_org context required for authenticated entitlement checks.
        # OrganizationLoader self-heals, so nil auth_org indicates a system issue.
        unless auth_org
          OT.le format('[require_entitlement!] No auth_org for %s (cust=%s)', entitlement, cust&.custid)
          raise Onetime::EntitlementRequired.new(
            entitlement,
            message: 'Unable to verify entitlements (organization context unavailable)',
          )
        end

        # Check if auth_org has the entitlement
        return true if auth_org.can?(entitlement)

        # Build upgrade path info
        current_plan = auth_org.planid
        upgrade_to   = if defined?(Billing::PlanHelpers)
                         Billing::PlanHelpers.upgrade_path_for(entitlement, current_plan)
                       end

        raise Onetime::EntitlementRequired.new(
          entitlement,
          current_plan: current_plan,
          upgrade_to: upgrade_to,
        )
      end

      # Safely extract session ID when the session object might be a Hash
      # (e.g. from BasicAuth) rather than a proper session with an #id method.
      def safe_session_id
        sess.id if sess.respond_to?(:id)
      end

      def custom_domain?
        domain_strategy.to_s == 'custom'
      end

      # Extract domain context from StrategyResult metadata
      #
      # @param strategy_result [Otto::Security::Authentication::StrategyResult]
      def extract_domain_context(strategy_result)
        return unless strategy_result

        @domain_strategy = strategy_result.metadata[:domain_strategy]
        @display_domain  = strategy_result.metadata[:display_domain]
      end

      # Session message helpers for user feedback
      def set_info_message(message)
        warn "[set_info_message] REMOVED #{message} via:"
        warn "[set_info_message] #{caller(1..3)}"
      end

      def set_error_message(message)
        warn "[set_error_message] REMOVED #{message} via:"
        warn "[set_error_message] #{caller(1..3)}"
      end

      # Requires the implementing class to have cust and session fields
      #
      # Used by:
      #   - AccountAPI::Logic::Account::CreateAccount
      #   - Core::Logic::Authentication::AuthenticateSession
      def send_verification_email(_token = nil)
        msg = format("Thanks for verifying your account. We got you a secret fortune cookie!\n\n\"%s\"", OT::Utils.random_fortune)

        _receipt, secret = Onetime::Receipt.spawn_pair(cust&.objid, 24.days, msg)

        secret.verification = true
        secret.custid       = cust.custid
        secret.save

        # The reset_secret field is a related standalone dbkey, writes
        # immediately. e.g. customer:abcd1234:reset_secret
        cust.reset_secret = secret.identifier

        begin
          Onetime::Mail::Mailer.deliver(
            :welcome,
            {
              email_address: cust.email,
              secret: secret,
            },
            locale: locale || 'en',
          )
        rescue StandardError => ex
          errmsg = "Couldn't send the verification email. Let us know below."
          OT.le "Error sending verification email: #{ex.message}", ex.backtrace
          set_info_message(errmsg)
        end
      end

      module ClassMethods
        def normalize_password(password, max_length = 128)
          password.to_s.strip.slice(0, max_length)
        end
      end

      extend ClassMethods
    end
  end
end
