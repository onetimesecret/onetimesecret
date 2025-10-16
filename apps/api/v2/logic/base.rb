# apps/api/v2/logic/base.rb

require 'timeout'

require 'onetime/refinements/stripe_refinements'

require_relative 'helpers'

module V2
  module Logic

    using Familia::Refinements::TimeLiterals

    class Base
      # We may want to have a @@customer_model set so that we can set it to
      # Onetime::Customer. Currently even if we're using the V2 of this logic,
      # it may still be running with V1::Customer in corner areas of the
      # code. If we decide to go that route (no pun intended) a class
      # variable is the way to go so that all logic subclasses can see the thing.
      include V2::Logic::I18nHelpers
      include V2::Logic::UriHelpers

      attr_reader :context, :sess, :cust, :params, :locale, :processed_params, :site, :authentication, :domains_enabled, :planid

      attr_accessor :domain_strategy, :display_domain

      def initialize(strategy_result, params, locale = nil)
        @strategy_result = strategy_result
        @params = params

        # Extract session and user from StrategyResult
        @sess = strategy_result.session
        @cust = strategy_result.user
        @locale = locale || @params[:locale] || @sess[:locale] || 'en'

        @processed_params ||= {} # TODO: Remove
        process_settings

        # Handle user model instances properly
        if @cust.nil?
          @cust = Onetime::Customer.anonymous
        elsif @cust.is_a?(String)
          OT.li "[#{self.class}] Friendly reminder to pass in a Customer instance instead of a custid"
          @cust = Onetime::Customer.load(@cust)
        end
        # If @cust is already a Onetime::Customer instance, use it as-is

        # Won't run if params aren't passed in
        process_params if respond_to?(:process_params) && @params
      end

      def process_settings
        @site            = OT.conf.fetch('site', {})
        site.fetch('domains', {})
        @authentication  = site.fetch('authentication', {})
        domains          = site.fetch('domains', {})
        @domains_enabled = domains['enabled'] || false
      end

      def valid_email?(guess)
        loggable_guess = OT::Utils.obscure_email(guess)
        OT.ld "[valid_email?] Guess: #{loggable_guess}"

        begin
        validator = Truemail.validate(guess)
        valid = validator.result.valid?
        validation_str = validator.as_json
        OT.info "[valid_email?] Address is valid (#{valid}): #{validation_str}"
        valid
      rescue StandardError => ex
        OT.le "Email validation error (#{loggable_guess}): #{ex.message}"
        OT.le ex.backtrace
        false
      end
      end

      def success_data
        raise NotImplementedError
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

      def custom_domain?
        domain_strategy.to_s == 'custom'
      end

      # Requires the implementing class to have cust and session fields
      def send_verification_email(token = nil)
        _, secret = Onetime::Secret.spawn_pair cust.custid, token

        OT.lw "[send_verification_email] DISABLED"
        return

        msg = "Thanks for verifying your account. We got you a secret fortune cookie!\n\n\"%s\"" % OT::Utils.random_fortune

        secret.encrypt_value msg
        secret.verification = true
        secret.custid       = cust.custid
        secret.save

        cust.reset_secret = secret.key # as a standalone dbkey, writes immediately

        view = Onetime::Mail::Welcome.new cust, locale, secret

        begin
          view.deliver_email token
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
