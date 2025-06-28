# apps/api/v2/logic/base.rb

require 'stathat'
require 'timeout'

require 'onetime/refinements/stripe_refinements'
require 'onetime/refinements/time_extensions'

require_relative 'helpers'

using Onetime::TimeExtensions

module V2
  module Logic
    class Base
      # We may want to have a @@customer_model set so that we can set it to
      # V2::Customer. Currently even if we're using the V2 of this logic,
      # it may still be running with V1::Customer in corner areas of the
      # code. If we decide to go that route (no pun intended) a class
      # variable is the way to go so that all logic subclasses can see the thing.
      include V2::Logic::I18nHelpers
      include V2::Logic::UriHelpers

      attr_reader :sess, :cust, :params, :locale, :processed_params, :plan, :site, :authentication, :domains_enabled

      attr_accessor :domain_strategy, :display_domain

      def initialize(sess, cust, params = nil, locale = nil)
        @sess               = sess
        @cust               = cust
        @params             = params
        @locale             = locale
        @processed_params ||= {} # TODO: Remove
        process_settings

        if cust.is_a?(String)
          OT.li "[#{self.class}] Friendly reminder to pass in a Customer instance instead of a custid"
          @cust = V2::Customer.load(cust)
        end

        # Won't run if params aren't passed in
        process_params if respond_to?(:process_params) && @params
      end

      def process_settings
        @site            = OT.conf.fetch(:site, {})
        domains          = site.fetch(:domains, {})
        @authentication  = site.fetch(:authentication, {})
        @domains_enabled = domains[:enabled] || false
      end

      def valid_email?(guess)
        OT.ld "[valid_email?] Guess: #{guess}"

        begin
          validator = Truemail.validate(guess)
        rescue StandardError => ex
          OT.le "Email validation error: #{ex.message}"
          OT.le ex.backtrace
          false
        else
          valid          = validator.result.valid?
          validation_str = validator.as_json
          OT.info "[valid_email?] Address is valid (#{valid}): #{validation_str}"
          valid
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

      def raise_form_error(msg)
        ex             = OT::FormError.new
        ex.message     = msg
        ex.form_fields = form_fields if respond_to?(:form_fields)
        raise ex
      end

      def plan
        @plan   = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
        @plan
      end

      def limit_action(event)
        disable_for_paid = plan && plan.paid?
        # This method is called a lot so we don't even attempt to log unless we're debugging
        OT.ld "[limit_action] #{event} (disable:#{disable_for_paid};sess:#{sess.class})" if OT.debug?
        return if disable_for_paid
        raise OT::Problem, 'No session to limit' unless sess

        sess.event_incr! event
      end

      def custom_domain?
        domain_strategy.to_s == 'custom'
      end

      # Requires the implementing class to have cust and session fields
      def send_verification_email(token = nil)
        _, secret = V2::Secret.spawn_pair cust.custid, token

        msg = <<~MSG.strip.format(OT::Utils.random_fortune)
          Thanks for verifying your account. We got you a secret fortune cookie!

          "%s"
        MSG

        secret.encrypt_value msg
        secret.verification = true
        secret.custid       = cust.custid
        secret.save

        cust.reset_secret = secret.key # as a standalone rediskey, writes immediately

        view = Onetime::Mail::Welcome.new cust, locale, secret

        begin
          view.deliver_email token
        rescue StandardError => ex
          errmsg = "Couldn't send the verification email. Let us know below."
          OT.le "Error sending verification email: #{ex.message}", ex.backtrace
          sess.set_info_message errmsg
        end
      end

      module ClassMethods
        def normalize_password(password, max_length = 128)
          password.to_s.strip.slice(0, max_length)
        end
      end

      extend ClassMethods
    end

    module ClassMethods
      attr_writer :stathat_apikey, :stathat_enabled

      def stathat_apikey
        @stathat_apikey ||= Onetime.conf&.dig(:stathat, :apikey)
      end

      def stathat_enabled
        return unless Onetime.conf&.key?(:stathat)

        @stathat_enabled = Onetime.conf&.dig(:stathat, :enabled) if @stathat_enabled.nil?
        @stathat_enabled
      end

      def stathat_count(name, count, wait = 0.500)
        return false unless stathat_enabled

        begin
          Timeout.timeout(wait) do
            StatHat::API.ez_post_count(name, stathat_apikey, count)
          end
        rescue SocketError => ex
          OT.info "Cannot connect to StatHat: #{ex.message}"
        rescue Timeout::Error
          OT.info 'timeout calling stathat'
        end
      end

      def stathat_value(name, value, wait = 0.500)
        return false unless stathat_enabled

        begin
          Timeout.timeout(wait) do
            StatHat::API.ez_post_value(name, stathat_apikey, value)
          end
        rescue SocketError => ex
          OT.info "Cannot connect to StatHat: #{ex.message}"
        rescue Timeout::Error
          OT.info 'timeout calling stathat'
        end
      end
    end

    extend ClassMethods
  end
end
