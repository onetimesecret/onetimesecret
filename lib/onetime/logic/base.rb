# lib/onetime/logic/base.rb
#
# frozen_string_literal: true

require 'sanitize'
require 'timeout'

require 'onetime/mail'
require 'onetime/refinements/stripe_refinements'
require 'onetime/logic/organization_context'
require 'onetime/security/input_sanitizers'

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

        # Extract organization and team context from StrategyResult metadata
        extract_organization_context(strategy_result)

        @processed_params ||= {} # TODO: Remove
        process_settings

        # Handle user model instances properly
        if @cust.nil?
          @cust = Onetime::Customer.anonymous
        elsif @cust.is_a?(String)
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

      def raise_not_found(msg)
        ex         = Onetime::RecordNotFound.new
        ex.message = msg
        raise ex
      end

      def raise_form_error(msg, field: nil, error_type: nil)
        ex             = OT::FormError.new(msg, field: field, error_type: error_type)
        ex.form_fields = form_fields if respond_to?(:form_fields)
        raise ex
      end

      # Require that the organization has a specific entitlement.
      # Raises EntitlementRequired with upgrade path if check fails.
      #
      # @param entitlement [String, Symbol] The entitlement to check
      # @raise [Onetime::EntitlementRequired] If org lacks the entitlement
      # @return [true] If entitlement check passes
      def require_entitlement!(entitlement)
        entitlement = entitlement.to_s

        # No org context means no entitlement check (public endpoints)
        return true unless org

        # Check if org has the entitlement
        return true if org.can?(entitlement)

        # Build upgrade path info
        current_plan = org.planid
        upgrade_to   = if defined?(Billing::PlanHelpers)
                         Billing::PlanHelpers.upgrade_path_for(entitlement, current_plan)
                       end

        raise Onetime::EntitlementRequired.new(
          entitlement,
          current_plan: current_plan,
          upgrade_to: upgrade_to,
        )
      end

      def custom_domain?
        domain_strategy.to_s == 'custom'
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

        _metadata, secret = Onetime::Metadata.spawn_pair(cust&.objid, 24.days, msg)

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
