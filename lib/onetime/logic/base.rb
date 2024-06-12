# typed: false

module Onetime
  module Logic
    class Base
      unless defined?(Onetime::Logic::Base::MOBILE_REGEX)
        MOBILE_REGEX = /^\+?\d{9,16}$/
        EMAIL_REGEX = /^(?:[_a-z0-9-]+)(\.[_a-z0-9-]+)*@([a-z0-9-]+)(\.[a-zA-Z0-9\-\.]+)*(\.[a-z]{2,12})$/i
      end

      attr_reader :sess, :cust, :params, :locale, :processed_params, :plan

      def initialize(sess, cust, params = nil, locale = nil)
        @sess = sess
        @cust = cust
        @params = params
        @locale = locale
        @processed_params ||= {} # TODO: Remove
        process_params if respond_to?(:process_params) && @params
        process_generic_params if @params # TODO: Remove
      end

      protected

      def process_params
        raise NotImplementedError, 'process_params not implemented'
      end

      # Generic params that can appear anywhere are processed here.
      # This is called in initialize AFTER process_params so that
      # values set here don't overwrite values that already exist.
      def process_generic_params
        raise NotImplementedError, 'process_generic_params not implemented'
      end

      def form_fields
        OT.ld "No form_fields method for #{self.class}"
        {}
      end

      def raise_form_error(msg)
        ex = OT::FormError.new
        ex.message = msg
        ex.form_fields = form_fields
        raise ex
      end

      def plan
        @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
      end

      def limit_action(event)
        return if plan.paid?

        sess.event_incr! event
      end

      def valid_email?(guess)
        !guess.to_s.match(EMAIL_REGEX).nil?
      end

      def valid_mobile?(guess)
        !guess.to_s.tr('-.', '').match(MOBILE_REGEX).nil?
      end
    end

    class << self
      attr_writer :stathat_apikey, :stathat_enabled

      def stathat_apikey
        @stathat_apikey ||= Onetime.conf[:stathat][:apikey]
      end

      def stathat_enabled
        return unless Onetime.conf.has_key?(:stathat)

        @stathat_enabled = Onetime.conf[:stathat][:enabled] if @stathat_enabled.nil?
        @stathat_enabled
      end

      def stathat_count(name, count, wait = 0.500)
        return false unless stathat_enabled

        begin
          Timeout.timeout(wait) do
            StatHat::API.ez_post_count(name, stathat_apikey, count)
          end
        rescue SocketError => e
          OT.info "Cannot connect to StatHat: #{e.message}"
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
        rescue SocketError => e
          OT.info "Cannot connect to StatHat: #{e.message}"
        rescue Timeout::Error
          OT.info 'timeout calling stathat'
        end
      end
    end
  end
end
