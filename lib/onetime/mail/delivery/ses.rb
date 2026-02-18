# lib/onetime/mail/delivery/ses.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Delivery
      # AWS SES v2 delivery backend.
      # Supports multipart text/HTML emails.
      #
      # Configuration options (via config hash or ENV):
      #   region:            AWS region (ENV: AWS_REGION, default: us-east-1)
      #   access_key_id:     AWS access key (ENV: AWS_ACCESS_KEY_ID)
      #   secret_access_key: AWS secret key (ENV: AWS_SECRET_ACCESS_KEY)
      #
      class SES < Base
        # AWS error codes indicating transient/throttling issues
        TRANSIENT_ERROR_CODES = %w[
          TooManyRequestsException
          LimitExceededException
          RequestThrottled
          ThrottlingException
          ServiceUnavailableException
        ].freeze

        # AWS error codes indicating permanent/configuration issues
        FATAL_ERROR_CODES = %w[
          MessageRejected
          AccountSendingPausedException
          MailFromDomainNotVerifiedException
          ConfigurationSetDoesNotExist
          InvalidParameterValue
          BadRequestException
        ].freeze

        def perform_delivery(email)
          OT.ld "[ses] Delivering to #{OT::Utils.obscure_email(email[:to])}"

          email_params = build_email_params(email)
          ses_client.send_email(email_params)
        end

        def classify_error(error)
          if error.respond_to?(:code)
            return :transient if TRANSIENT_ERROR_CODES.include?(error.code)
            return :fatal if FATAL_ERROR_CODES.include?(error.code)
          end

          if error.respond_to?(:http_status_code)
            return :transient if error.http_status_code == 429 || error.http_status_code >= 500
            return :fatal if error.http_status_code >= 400
          end

          super
        end

        protected

        def validate_config!
          access_key = config[:access_key_id] || ENV.fetch('AWS_ACCESS_KEY_ID', nil)
          secret_key = config[:secret_access_key] || ENV.fetch('AWS_SECRET_ACCESS_KEY', nil)

          if access_key.nil? || access_key.empty? || secret_key.nil? || secret_key.empty?
            raise ArgumentError, 'AWS credentials must be configured for SES'
          end
        end

        private

        def build_email_params(email)
          body = {
            text: {
              data: email[:text_body],
              charset: 'UTF-8',
            },
          }

          # Add HTML part if present
          if html_content?(email)
            body[:html] = {
              data: email[:html_body],
              charset: 'UTF-8',
            }
          end

          params = {
            destination: {
              to_addresses: [email[:to]],
            },
            content: {
              simple: {
                subject: {
                  data: email[:subject],
                  charset: 'UTF-8',
                },
                body: body,
              },
            },
            from_email_address: email[:from],
          }

          # Add reply-to if present
          if email[:reply_to] && !email[:reply_to].empty?
            params[:reply_to_addresses] = [email[:reply_to]]
          end

          params
        end

        def ses_client
          @ses_client ||= begin
            require 'aws-sdk-sesv2'

            # Configure with explicit credentials
            region     = config[:region] || ENV['AWS_REGION'] || 'us-east-1'
            access_key = config[:access_key_id] || ENV.fetch('AWS_ACCESS_KEY_ID', nil)
            secret_key = config[:secret_access_key] || ENV.fetch('AWS_SECRET_ACCESS_KEY', nil)

            Aws::SESV2::Client.new(
              region: region,
              credentials: Aws::Credentials.new(access_key, secret_key),
            )
          end
        end
      end
    end
  end
end
