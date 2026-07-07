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

        # process_params runs on EVERY request and fires here in the
        # constructor — BEFORE raise_concerns, so no auth/validation gating has
        # happened yet. On auth=noauth routes cust is nil for anonymous callers
        # (authenticated-only routes are rejected at the Otto auth layer, so
        # their cust is always present). Subclasses reachable via noauth routes
        # must therefore guard cust access in process_params. See #3516.
        #
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
        ex             = OT::FormError.new(
          msg,
          error_key: error_key,
          args: args,
          field: field,
          error_type: error_type,
        )
        ex.form_fields = form_fields if respond_to?(:form_fields)
        raise ex
      end

      # Server-enforced ceiling on secret body size, shared by the regular
      # (V2 ConcealSecret) and incoming (V3 CreateIncomingSecret) paths.
      # Reads the single source of truth at
      # site.secret_options.content.maximum_length, which is also exposed to
      # the frontend as the textarea hint — keeping the client limit and the
      # server limit from drifting. Presence (empty/nil) is the caller's
      # responsibility; this only rejects content that exceeds the ceiling.
      #
      # @sync src/schemas/contracts/config/public.ts — secret_options.content
      def validate_secret_size(value)
        # Normalize once so the comparison and the error message agree and a
        # Float from config never renders as "10000.0".
        max_length = (OT.conf.dig('site', 'secret_options', 'content', 'maximum_length') || 10_000).to_i
        return if value.to_s.length <= max_length

        raise_form_error "Secret content must be no more than #{max_length} characters long",
          field: :secret
      end

      # Require that the authenticated user's membership has a specific entitlement.
      # Raises EntitlementRequired with upgrade path if check fails.
      #
      # ADR-012 Stage 3: Authorization checks use auth_membership.can?, not auth_org.can?.
      # The membership is the single source of truth for "what can this caller do in this org."
      # Effective entitlements are: org.entitlements ∩ ROLE_ENTITLEMENTS[role] + grants - revokes.
      #
      # For anonymous users (noauth routes), entitlement checks are skipped.
      # Guest route gating (GuestRouteGating concern) handles access control
      # for anonymous requests separately.
      #
      # @param entitlement [String, Symbol] The entitlement to check
      # @param error_key [String, nil] Optional dotted i18n key for the raised
      #   error. Defaults to "api.entitlements.errors.#{entitlement}_required".
      #   The "no auth_org/auth_membership" path uses a fixed system-error key
      #   ('api.entitlements.errors.context_unavailable') and ignores this arg.
      # @raise [Onetime::EntitlementRequired] If membership lacks the entitlement
      # @return [true] If entitlement check passes
      def require_entitlement!(entitlement, error_key: nil)
        entitlement = entitlement.to_s
        error_key ||= "api.entitlements.errors.#{entitlement}_required"

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
            error_key: 'api.entitlements.errors.context_unavailable',
            args: { entitlement: entitlement },
          )
        end

        # Fail-closed: auth_membership required for authenticated entitlement checks.
        # Missing membership for an authenticated user indicates a system issue —
        # the customer should always have a membership in their auth_org.
        unless auth_membership
          OT.le format(
            '[require_entitlement!] No auth_membership for %s (cust=%s, org=%s)',
            entitlement,
            cust&.custid,
            auth_org&.extid,
          )
          raise Onetime::EntitlementRequired.new(
            entitlement,
            message: 'Unable to verify entitlements (membership context unavailable)',
            error_key: 'api.entitlements.errors.context_unavailable',
            args: { entitlement: entitlement },
          )
        end

        # Fail-closed: membership must be active.
        unless auth_membership.active?
          OT.le format(
            '[require_entitlement!] auth_membership not active for %s (cust=%s, org=%s, status=%s)',
            entitlement,
            cust&.custid,
            auth_org&.extid,
            auth_membership.status,
          )
          raise Onetime::EntitlementRequired.new(
            entitlement,
            message: 'Unable to verify entitlements (membership not active)',
            error_key: 'api.entitlements.errors.context_unavailable',
            args: { entitlement: entitlement },
          )
        end

        # Check if auth_membership has the entitlement (ADR-012 Stage 3)
        return true if auth_membership.can?(entitlement)

        # Build upgrade path info
        current_plan = auth_org.planid
        upgrade_to   = if defined?(Billing::PlanHelpers)
                         Billing::PlanHelpers.upgrade_path_for(entitlement, current_plan)
                       end

        raise Onetime::EntitlementRequired.new(
          entitlement,
          current_plan: current_plan,
          upgrade_to: upgrade_to,
          error_key: error_key,
          args: { entitlement: entitlement },
        )
      end

      # Require that the user's membership in a specific organization has an entitlement.
      #
      # Unlike require_entitlement! (which checks auth_membership in auth_org),
      # this method checks the user's membership in a *target* organization.
      # Used by Organization API endpoints that operate on organizations loaded
      # from URL parameters rather than the user's auth context.
      #
      # @param organization [Onetime::Organization] The target organization
      # @param entitlement [String, Symbol] The entitlement to check
      # @param error_key [String, nil] Optional i18n key for the raised error
      # @raise [Onetime::EntitlementRequired] If membership lacks the entitlement
      # @raise [Onetime::Forbidden] If user is not a member of the organization
      # @return [true] If entitlement check passes
      def require_entitlement_in!(organization, entitlement, error_key: nil)
        raise Onetime::Problem, 'Organization context unavailable' if organization.nil?

        entitlement = entitlement.to_s
        error_key ||= "api.entitlements.errors.#{entitlement}_required"

        # Colonels (site admins) bypass all entitlement checks
        return true if has_system_role?('colonel')

        # Anonymous users can't have entitlements in any organization
        if anonymous_user?
          raise Onetime::Forbidden.new(
            'Authentication required',
            error_key: 'api.errors.authentication_required',
          )
        end

        # Load user's membership in the target organization
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid,
          cust.objid,
        )

        # User must be a member of the target organization
        unless membership&.active?
          raise Onetime::Forbidden.new(
            'You must be a member of this organization',
            error_key: 'api.organizations.errors.organization_member_required',
          )
        end

        # Check if membership has the entitlement
        return true if membership.can?(entitlement)

        # Build upgrade path info
        current_plan = organization.planid
        upgrade_to   = if defined?(Billing::PlanHelpers)
                         Billing::PlanHelpers.upgrade_path_for(entitlement, current_plan)
                       end

        raise Onetime::EntitlementRequired.new(
          entitlement,
          current_plan: current_plan,
          upgrade_to: upgrade_to,
          error_key: error_key,
          args: { entitlement: entitlement },
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

      # Send (or resend) a verification email.
      #
      # @param customer [Onetime::Customer] the recipient. Defaults to the
      #   request-context `cust`. Unauthenticated flows (e.g. the public
      #   password-reset request) have a nil `cust`, so they MUST pass the
      #   looked-up customer explicitly — otherwise the verification secret binds
      #   to nil and the request 500s.
      #
      # Used by:
      #   - AccountAPI::Logic::Account::CreateAccount (implicit cust)
      #   - Core::Logic::Authentication::AuthenticateSession (implicit cust)
      #   - AccountAPI::Logic::Authentication::ResetPasswordRequest (explicit)
      def send_verification_email(_token = nil, customer: cust)
        msg = format("Thanks for verifying your account. We got you a secret fortune cookie!\n\n\"%s\"", OT::Utils.random_fortune)

        _receipt, secret = Onetime::Receipt.spawn_pair(customer&.objid, 24.days, msg)

        secret.verification = true
        secret.custid       = customer.custid
        secret.save

        # The reset_secret field is a related standalone dbkey, writes
        # immediately. e.g. customer:abcd1234:reset_secret
        customer.reset_secret = secret.identifier

        begin
          Onetime::Mail::Mailer.deliver(
            :welcome,
            {
              email_address: customer.email,
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
