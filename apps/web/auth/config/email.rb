# apps/web/auth/config/email.rb

require 'net/smtp'

module Auth
  module Config
    module Email
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
            provider_info = provider ? " via #{provider}" : ""
            OT.info "[email] #{status.capitalize} email to #{email[:to]}#{provider_info}: #{email[:subject]}"
          end

          def log_error(email, error, provider = nil)
            provider_info = provider ? " via #{provider}" : ""
            OT.le "[email] Failed to send email to #{email[:to]}#{provider_info}: #{error.message}"
          end
        end

        class Logger < Base
          def deliver(email)
            puts "\n=== EMAIL DEBUG ==="
            puts "Provider: Logger"
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
            smtp_host = @config[:host] || ENV['SMTP_HOST'] || 'localhost'
            smtp_port = (@config[:port] || ENV['SMTP_PORT'] || '587').to_i
            username = @config[:username] || ENV['SMTP_USERNAME']
            password = @config[:password] || ENV['SMTP_PASSWORD']
            use_tls = @config[:tls].nil? ? (ENV['SMTP_TLS'] != 'false') : @config[:tls]
            auth_method = @config[:auth_method] || ENV['SMTP_AUTH_METHOD'] || 'plain'

            message = build_message(email)

            smtp = Net::SMTP.new(smtp_host, smtp_port)
            smtp.enable_starttls_auto if use_tls
            smtp.start('localhost', username, password, auth_method.to_sym) do |smtp_session|
              smtp_session.send_message(message, email[:from], email[:to])
            end

            log_delivery(email, 'sent', 'SMTP')
          rescue StandardError => e
            log_error(email, e, 'SMTP')
            raise e
          end

          protected

          def validate_config!
            host = @config[:host] || ENV['SMTP_HOST']
            raise ArgumentError, "SMTP host must be configured" if host.nil? || host.empty?
          end

          def build_message(email)
            <<~MESSAGE
              From: #{email[:from]}
              To: #{email[:to]}
              Subject: #{email[:subject]}
              Content-Type: text/plain; charset=UTF-8

              #{email[:body]}
            MESSAGE
          end
        end

        class SendGrid < Base
          def deliver(email)
            require 'net/http'
            require 'json'

            api_key = @config[:api_key] || ENV['SENDGRID_API_KEY']

            payload = {
              personalizations: [{
                to: [{ email: email[:to] }],
                subject: email[:subject]
              }],
              from: { email: email[:from] },
              content: [{
                type: 'text/plain',
                value: email[:body]
              }]
            }

            uri = URI('https://api.sendgrid.com/v3/mail/send')
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true

            request = Net::HTTP::Post.new(uri)
            request['Authorization'] = "Bearer #{api_key}"
            request['Content-Type'] = 'application/json'
            request.body = payload.to_json

            response = http.request(request)

            if response.code.to_i >= 200 && response.code.to_i < 300
              log_delivery(email, 'sent', 'SendGrid')
            else
              raise "SendGrid API error: #{response.code} #{response.body}"
            end
          rescue StandardError => e
            log_error(email, e, 'SendGrid')
            raise e
          end

          protected

          def validate_config!
            api_key = @config[:api_key] || ENV['SENDGRID_API_KEY']
            raise ArgumentError, "SendGrid API key must be configured" if api_key.nil? || api_key.empty?
          end
        end

        class SES < Base
          def deliver(email)
            require 'aws-sdk-ses'

            region = @config[:region] || ENV['AWS_REGION'] || 'us-east-1'
            access_key = @config[:access_key_id] || ENV['AWS_ACCESS_KEY_ID']
            secret_key = @config[:secret_access_key] || ENV['AWS_SECRET_ACCESS_KEY']

            client = Aws::SES::Client.new(
              region: region,
              access_key_id: access_key,
              secret_access_key: secret_key
            )

            client.send_email({
              source: email[:from],
              destination: {
                to_addresses: [email[:to]]
              },
              message: {
                subject: {
                  data: email[:subject],
                  charset: 'UTF-8'
                },
                body: {
                  text: {
                    data: email[:body],
                    charset: 'UTF-8'
                  }
                }
              }
            })

            log_delivery(email, 'sent', 'SES')
          rescue StandardError => e
            log_error(email, e, 'SES')
            raise e
          end

          protected

          def validate_config!
            access_key = @config[:access_key_id] || ENV['AWS_ACCESS_KEY_ID']
            secret_key = @config[:secret_access_key] || ENV['AWS_SECRET_ACCESS_KEY']

            if access_key.nil? || access_key.empty? || secret_key.nil? || secret_key.empty?
              raise ArgumentError, "AWS credentials must be configured for SES"
            end
          end
        end

        class Mailpit < Base
          def deliver(email)
            # Support legacy MAILPIT_SMTP_HOST for backward compatibility
            smtp_host = @config[:host] || ENV['MAILPIT_HOST'] || ENV['MAILPIT_SMTP_HOST'] || 'localhost'
            smtp_port = (@config[:port] || ENV['MAILPIT_PORT'] || ENV['MAILPIT_SMTP_PORT'] || '1025').to_i

            message = <<~EMAIL
              From: #{email[:from]}
              To: #{email[:to]}
              Subject: #{email[:subject]}

              #{email[:body]}
            EMAIL

            Net::SMTP.start(smtp_host, smtp_port) do |smtp|
              smtp.send_message(message, email[:from], email[:to])
            end

            log_delivery(email, 'sent', 'Mailpit')
          rescue StandardError => e
            log_error(email, e, 'Mailpit')
            raise e
          end
        end
      end

      class Configuration
        attr_reader :provider, :delivery_strategy

        def initialize
          @provider = determine_provider
          @delivery_strategy = create_delivery_strategy
          @from_address = determine_from_address
          @subject_prefix = determine_subject_prefix

          validate_configuration!
        end

        def from_address
          @from_address
        end

        def subject_prefix
          @subject_prefix
        end

        def deliver_email(email)
          # Add configured defaults to email
          email = email.merge(
            from: email[:from] || @from_address,
            subject: "#{@subject_prefix}#{email[:subject]}"
          )

          case ENV['EMAIL_DELIVERY_MODE']&.downcase
          when 'async'
            # Future: implement async delivery
            @delivery_strategy.deliver(email)
          when 'test'
            Delivery::Logger.new.deliver(email)
          else
            @delivery_strategy.deliver(email)
          end
        end

        private

        def determine_provider
          provider = ENV['EMAIL_PROVIDER']&.downcase

          # Auto-detect based on available configuration
          if provider.nil?
            if ENV['RACK_ENV'] == 'test'
              'logger'
            elsif ENV['SENDGRID_API_KEY']
              'sendgrid'
            elsif ENV['AWS_ACCESS_KEY_ID'] && ENV['AWS_SECRET_ACCESS_KEY']
              'ses'
            elsif ENV['MAILPIT_HOST'] || ENV.key?('MAILPIT_PORT') || ENV['MAILPIT_SMTP_HOST']
              'mailpit'
            elsif ENV['SMTP_HOST']
              'smtp'
            else
              'logger'
            end
          else
            provider
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
          when 'mailpit'
            Delivery::Mailpit.new
          when 'logger'
            Delivery::Logger.new
          else
            OT.le "[email] Unknown email provider '#{@provider}', falling back to logger"
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
            raise ArgumentError, "Email from address must be configured"
          end

          # Validate the delivery strategy
          @delivery_strategy # This will raise if configuration is invalid
        rescue ArgumentError => e
          OT.le "[email] Configuration error: #{e.message}"
          OT.le "[email] Falling back to logger for email delivery"
          @delivery_strategy = Delivery::Logger.new
          @provider = 'logger'
        end
      end

      def self.configure(rodauth_config)
        rodauth_config.instance_eval do
          # Configure Rodauth email settings - use lazy evaluation
          email_from ENV['EMAIL_FROM'] || 'noreply@onetimesecret.com'
          email_subject_prefix ENV['EMAIL_SUBJECT_PREFIX'] || '[OneTimeSecret] '

          # Configure email delivery with lazy initialization
          send_email do |email|
            if ENV['RACK_ENV'] == 'test'
              OT.info "[email] Skipping email delivery in test environment: #{email[:subject]}"
            else
              begin
                # Create email config at delivery time to avoid early loading issues
                email_config = Configuration.new
                email_config.deliver_email(email)
              rescue StandardError => e
                OT.le "[email] Failed to deliver email: #{e.message}"
                # In production, we might want to queue for retry or use a fallback
                # For now, we'll just log the error
                raise e unless ENV['RACK_ENV'] == 'production'
              end
            end
          end
        end

        # Log the provider that will be used without creating the config
        provider = determine_provider_for_logging
        OT.info "[email] Email delivery will use #{provider} provider"
      end

      private_class_method def self.determine_provider_for_logging
        provider = ENV['EMAIL_PROVIDER']&.downcase

        if provider.nil?
          if ENV['RACK_ENV'] == 'test'
            'logger'
          elsif ENV['SENDGRID_API_KEY']
            'sendgrid'
          elsif ENV['AWS_ACCESS_KEY_ID'] && ENV['AWS_SECRET_ACCESS_KEY']
            'ses'
          elsif ENV['MAILPIT_HOST'] || ENV.key?('MAILPIT_PORT') || ENV['MAILPIT_SMTP_HOST']
            'mailpit'
          elsif ENV['SMTP_HOST']
            'smtp'
          else
            'logger'
          end
        else
          provider
        end
      end
    end
  end
end
