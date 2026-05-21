# apps/api/v1/logic/base.rb
#
# frozen_string_literal: true

require 'timeout'

require_relative 'helpers'
require 'onetime/security/input_sanitizers'

module V1
  module Logic
    class Base
      using Familia::Refinements::TimeLiterals

      include V1::Logic::UriHelpers
      include Onetime::Security::InputSanitizers

      attr_reader :sess, :cust, :params, :locale, :processed_params
      attr_reader :site, :authentication, :domains_enabled

      attr_accessor :domain_strategy, :display_domain

      def initialize(sess, cust, params = nil, locale = nil)
        @sess = sess
        @cust = cust
        @params = params
        @locale = locale
        @processed_params ||= {} # TODO: Remove
        process_settings

        if cust.is_a?(String)
          OT.li "[#{self.class}] Friendly reminder to pass in a Customer instance instead of a custid"
          @cust = Onetime::Customer.load_by_extid_or_email(cust)
        end

        # Won't run if params aren't passed in
        process_params if respond_to?(:process_params) && @params
      end

      def process_settings
        @site = OT.conf.fetch('site', {})
        domains = site.fetch('domains', {})
        @authentication = site.fetch('authentication', {})
        domains = site.fetch('domains', {})
        @domains_enabled = domains['enabled'] || false
      end

      def valid_email?(email_field)
        OT.ld "[valid_email?] Email field: #{email_field}"

        begin
          validator = Truemail.validate(email_field)

        rescue StandardError => e
          OT.le "Email validation error: #{e.message}"
          OT.le e.backtrace
          false
        else
          valid = validator.result.valid?
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
        ex = Onetime::RecordNotFound.new
        ex.message = msg
        raise ex
      end

      def raise_form_error(msg, field: nil, error_type: nil)
        ex = OT::FormError.new(msg, field: field, error_type: error_type)
        ex.form_fields = form_fields if respond_to?(:form_fields)
        raise ex
      end

      def custom_domain?
        domain_strategy.to_s == 'custom'
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
