# frozen_string_literal: true

require 'stathat'
require 'timeout'

require_relative 'logic_helpers'

module Onetime
  module Logic
    class Base
      include LogicHelpers

      attr_reader :sess, :cust, :params, :locale, :processed_params, :plan
      attr_reader :site, :authentication, :domains_enabled

      def initialize(sess, cust, params = nil, locale = nil)
        @sess = sess
        @cust = cust
        @params = params
        @locale = locale
        @processed_params ||= {} # TODO: Remove
        process_settings
        process_params if respond_to?(:process_params) && @params
      end

      def process_settings
        @site = OT.conf.fetch(:site, {})
        domains = site.fetch(:domains, {})
        @authentication = site.fetch(:authentication, {})
        domains = site.fetch(:domains, {})
        @domains_enabled = domains[:enabled] || false
      end

      def valid_email?(guess)
        OT.ld "[valid_email?] Guess: #{guess}"

        begin
          validator = Truemail.validate(guess)

        rescue StandardError => e
          OT.le "Email validation error: #{e.message}"
          OT.le e.backtrace
          false
        else
          valid = validator.result.valid?
          validation_str = validator.as_json
          OT.info "[valid_email?] Validator (#{valid}): #{validation_str}"
          valid
        end
      end

      protected

      def process_params
        raise NotImplementedError, 'process_params not implemented'
      end

      def form_fields
        OT.ld "No form_fields method for #{self.class} via:", caller[0..2].join("\n")
        {}
      end

      def raise_form_error(msg)
        ex = OT::FormError.new
        ex.message = msg
        ex.form_fields = form_fields if respond_to?(:form_fields)
        raise ex
      end

      def plan
        @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
        @plan
      end

      def limit_action(event)
        return if plan && plan.paid?

        sess.event_incr! event
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

    extend ClassMethods
  end
end
