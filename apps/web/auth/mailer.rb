# apps/web/auth/config/email.rb
#
# frozen_string_literal: true

require 'net/smtp'

module Auth
  # Email delivery using standard Mail gem for SMTP, custom implementations for SendGrid/SES
  module Mailer
    # Email delivery strategies for different providers
    module Delivery
      class Base
        def initialize(config = {})
          @config = config
          validate_config!
        end

        def deliver(email)
          raise NotImplementedError, "#{self.class} must implement #deliver"
        end

        protected

        def validate_config!
          # Override in subclasses for provider-specific validation
        end

        def log_delivery(email, status = 'sent', provider = nil)
          provider_info = provider ? " via #{provider}" : ''
          OT.info "[email] #{status.capitalize} email to #{email[:to]}#{provider_info}: #{email[:subject]}"
        end

        def log_error(email, error, provider = nil)
          Onetime.get_logger('Auth').error 'Email delivery failed',
            to: email[:to],
            subject: email[:subject],
            provider: provider,
            error: error.message
        end
      end

      class Logger < Base
        def deliver(email)
          puts "\n=== EMAIL DEBUG ==="
          puts 'Provider: Logger'
          puts "To: #{email[:to]}"
          puts "From: #{email[:from]}"
          puts "Subject: #{email[:subject]}"
          puts "Body:\n#{email[:body]}"
          puts "=== END EMAIL ===\n"
          log_delivery(email, 'logged', 'Logger')
        end
      end

      class SMTP < Base
        def deliver(email)
          require 'mail'

          mail = build_mail_message(email)
          settings = smtp_settings

          log_smtp_attempt(settings, email[:to])

          begin
            deliver_with_settings(mail, settings)
          rescue Net::SMTPAuthenticationError => ex
            handle_auth_failure(mail, settings, ex)
          end

          log_delivery(email, 'sent', 'SMTP')
        rescue StandardError => ex
          log_error(email, ex, 'SMTP')
          raise ex
        end

        private

        def build_mail_message(email)
          Mail.new do
            to      email[:to]
            from    email[:from]
            subject email[:subject]
            body    email[:body]
          end
        end

        def deliver_with_settings(mail, settings)
          mail.delivery_method :smtp, settings
          mail.deliver!

          has_auth = settings.key?(:user_name)
          Onetime.get_logger('Auth').debug 'SMTP delivery successful',
            host: settings[:address],
            port: settings[:port],
            authentication_used: has_auth
        end

        def handle_auth_failure(mail, settings, error)
          # Server doesn't support authentication or rejected credentials
          # Common with development SMTP servers like Mailpit that don't require auth
          Onetime.get_logger('Auth').info 'SMTP authentication failed, retrying without auth',
            host: settings[:address],
            port: settings[:port],
            error_message: error.message,
            original_auth_method: settings[:authentication],
            fallback_strategy: 'remove_authentication'

          # Retry without authentication
          settings_no_auth = settings.reject { |k, _v| [:user_name, :password, :authentication].include?(k) }
          mail.delivery_method :smtp, settings_no_auth
          mail.deliver!

          Onetime.get_logger('Auth').info 'SMTP delivery successful without authentication',
            host: settings[:address],
            port: settings[:port],
            note: 'Server does not support or require authentication'
        end

        def log_smtp_attempt(settings, recipient)
          has_auth = settings.key?(:user_name) && settings.key?(:password)

          Onetime.get_logger('Auth').debug 'SMTP delivery attempt',
            host: settings[:address],
            port: settings[:port],
            tls: settings[:enable_starttls_auto],
            authentication: has_auth ? settings[:authentication] : 'none',
            to: recipient
        end

        def validate_config!
          host = @config[:host] || ENV.fetch('SMTP_HOST', nil)
          raise ArgumentError, 'SMTP host must be configured' if host.nil? || host.empty?
        end

        def smtp_settings
          settings = {
            address: @config[:host] || ENV['SMTP_HOST'] || 'localhost',
            port: (@config[:port] || ENV['SMTP_PORT'] || '587').to_i,
            enable_starttls_auto: @config[:tls].nil? ? (ENV['SMTP_TLS'] != 'false') : @config[:tls],
          }

          # Only add authentication if credentials are provided
          username = @config[:username] || ENV.fetch('SMTP_USERNAME', nil)
          password = @config[:password] || ENV.fetch('SMTP_PASSWORD', nil)

          if username && password
            settings[:user_name] = username
            settings[:password] = password
            settings[:authentication] = :plain
          end

          settings
        end
      end

      class SendGrid < Base
        def deliver(email)
          require 'net/http'
          require 'json'

          api_key = @config[:api_key] || ENV.fetch('SENDGRID_API_KEY', nil)

          payload = {
            personalizations: [{
              to: [{ email: email[:to] }],
              subject: email[:subject],
            }],
            from: { email: email[:from] },
            content: [{
              type: 'text/plain',
              value: email[:body],
            }],
          }

          uri          = URI('https://api.sendgrid.com/v3/mail/send')
          http         = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request                  = Net::HTTP::Post.new(uri)
          request['Authorization'] = "Bearer #{api_key}"
          request['Content-Type']  = 'application/json'
          request.body             = payload.to_json

          response = http.request(request)

          raise "SendGrid API error: #{response.code} #{response.body}" unless response.code.to_i >= 200 && response.code.to_i < 300

          log_delivery(email, 'sent', 'SendGrid')
        rescue StandardError => ex
          log_error(email, ex, 'SendGrid')
          raise ex
        end

        protected

        def validate_config!
          api_key = @config[:api_key] || ENV.fetch('SENDGRID_API_KEY', nil)
          raise ArgumentError, 'SendGrid API key must be configured' if api_key.nil? || api_key.empty?
        end
      end

      class SES < Base
        def deliver(email)
          require 'aws-sdk-ses'

          region     = @config[:region] || ENV['AWS_REGION'] || 'us-east-1'
          access_key = @config[:access_key_id] || ENV.fetch('AWS_ACCESS_KEY_ID', nil)
          secret_key = @config[:secret_access_key] || ENV.fetch('AWS_SECRET_ACCESS_KEY', nil)

          client = Aws::SES::Client.new(
            region: region,
            access_key_id: access_key,
            secret_access_key: secret_key,
          )

          client.send_email({
            source: email[:from],
            destination: {
              to_addresses: [email[:to]],
            },
            message: {
              subject: {
                data: email[:subject],
                charset: 'UTF-8',
              },
              body: {
                text: {
                  data: email[:body],
                  charset: 'UTF-8',
                },
              },
            },
          },
                            )

          log_delivery(email, 'sent', 'SES')
        rescue StandardError => ex
          log_error(email, ex, 'SES')
          raise ex
        end

        protected

        def validate_config!
          access_key = @config[:access_key_id] || ENV.fetch('AWS_ACCESS_KEY_ID', nil)
          secret_key = @config[:secret_access_key] || ENV.fetch('AWS_SECRET_ACCESS_KEY', nil)

          if access_key.nil? || access_key.empty? || secret_key.nil? || secret_key.empty?
            raise ArgumentError, 'AWS credentials must be configured for SES'
          end
        end
      end
    end

    class Configuration
      attr_reader :provider, :delivery_strategy, :from_address, :subject_prefix

      def initialize
        @provider          = determine_provider
        @delivery_strategy = create_delivery_strategy
        @from_address      = determine_from_address
        @subject_prefix    = determine_subject_prefix

        validate_configuration!
      end

      def deliver_email(email)
        # Convert Mail::Message to hash format if needed
        email_hash = normalize_email(email)

        case ENV['EMAIL_DELIVERY_MODE']&.downcase
        when 'async'
          # Future: implement async delivery
          @delivery_strategy.deliver(email_hash)
        when 'test'
          Delivery::Logger.new.deliver(email_hash)
        else
          @delivery_strategy.deliver(email_hash)
        end
      end

      private

      def normalize_email(email)
        if email.respond_to?(:to) && email.respond_to?(:from) && email.respond_to?(:subject)
          # It's a Mail::Message object from Rodauth
          # Rodauth already handles email_from and email_subject_prefix configuration
          {
            to: safe_extract_email_address(email.to),
            from: safe_extract_email_address(email.from),
            subject: safe_extract_string(email.subject),
            body: safe_extract_string(email.body),
          }
        else
          # It's already a hash, ensure basic structure
          email_hash = email.is_a?(Hash) ? email : {}
          {
            to: email_hash[:to]&.to_s || '',
            from: email_hash[:from]&.to_s || @from_address,
            subject: email_hash[:subject]&.to_s || '',
            body: email_hash[:body]&.to_s || '',
          }
        end
      end

      def safe_extract_email_address(field)
        return '' if field.nil?

        if field.respond_to?(:first) && field.respond_to?(:empty?)
          # It's an array-like object
          field.empty? ? '' : field.first.to_s
        else
          # It's a string or string-like object
          field.to_s
        end
      end

      def safe_extract_string(field)
        return '' if field.nil?

        field.to_s
      end

      def determine_provider
        # Use EMAILER_MODE consistent with Onetime patterns
        mode = ENV['EMAILER_MODE']&.downcase

        # Debug logging
        Onetime.get_logger('Auth').debug 'Email provider detection',
          emailer_mode: mode,
          smtp_host: ENV.fetch('SMTP_HOST', nil),
          sendgrid_api_key: ENV['SENDGRID_API_KEY'] ? 'configured' : nil,
          aws_credentials: ENV.fetch('AWS_ACCESS_KEY_ID', nil) && ENV.fetch('AWS_SECRET_ACCESS_KEY', nil) ? 'configured' : nil

        # Auto-detect based on available configuration
        if mode.nil?
          if ENV['RACK_ENV'] == 'test'
            'logger'
          elsif ENV['SENDGRID_API_KEY']
            'sendgrid'
          elsif ENV['AWS_ACCESS_KEY_ID'] && ENV['AWS_SECRET_ACCESS_KEY']
            'ses'
          elsif ENV['SMTP_HOST']
            'smtp'
          else
            'logger'
          end
        else
          mode
        end
      end

      def create_delivery_strategy
        case @provider
        when 'smtp'
          Delivery::SMTP.new
        when 'sendgrid'
          Delivery::SendGrid.new
        when 'ses'
          Delivery::SES.new
        when 'logger'
          Delivery::Logger.new
        else
          Onetime.get_logger('Auth').warn 'Unknown email provider configured, falling back to logger',
            provider: @provider,
            fallback: 'logger'
          Delivery::Logger.new
        end
      end

      def determine_from_address
        ENV['EMAIL_FROM'] || 'noreply@onetimesecret.com'
      end

      def determine_subject_prefix
        ENV['EMAIL_SUBJECT_PREFIX'] || '[OneTimeSecret] '
      end

      def validate_configuration!
        if @from_address.nil? || @from_address.empty?
          raise ArgumentError, 'Email from address must be configured'
        end

        # Validate the delivery strategy
        @delivery_strategy # This will raise if configuration is invalid
      rescue ArgumentError => ex
        Onetime.auth_logger.error 'Email configuration invalid, falling back to logger delivery', {
          error: ex.message,
          fallback_provider: 'logger'
        }
        @delivery_strategy = Delivery::Logger.new
        @provider          = 'logger'
      end
    end
  end
end
