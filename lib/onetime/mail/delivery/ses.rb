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
        def deliver(email)
          email = normalize_email(email)

          OT.ld "[ses] Delivering to #{OT::Utils.obscure_email(email[:to])}"

          email_params = build_email_params(email)
          response = ses_client.send_email(email_params)

          log_delivery(email)
          response
        rescue Aws::SESV2::Errors::ServiceError => ex
          log_error(email, ex)
          raise
        rescue StandardError => ex
          log_error(email, ex)
          raise
        end

        protected

        def validate_config!
          access_key = config[:access_key_id] || ENV['AWS_ACCESS_KEY_ID']
          secret_key = config[:secret_access_key] || ENV['AWS_SECRET_ACCESS_KEY']

          if access_key.nil? || access_key.empty? || secret_key.nil? || secret_key.empty?
            raise ArgumentError, 'AWS credentials must be configured for SES'
          end
        end

        private

        def build_email_params(email)
          body = {
            text: {
              data: email[:text_body],
              charset: 'UTF-8'
            }
          }

          # Add HTML part if present
          if html_content?(email)
            body[:html] = {
              data: email[:html_body],
              charset: 'UTF-8'
            }
          end

          params = {
            destination: {
              to_addresses: [email[:to]]
            },
            content: {
              simple: {
                subject: {
                  data: email[:subject],
                  charset: 'UTF-8'
                },
                body: body
              }
            },
            from_email_address: email[:from]
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
            region = config[:region] || ENV['AWS_REGION'] || 'us-east-1'
            access_key = config[:access_key_id] || ENV['AWS_ACCESS_KEY_ID']
            secret_key = config[:secret_access_key] || ENV['AWS_SECRET_ACCESS_KEY']

            Aws::SESV2::Client.new(
              region: region,
              credentials: Aws::Credentials.new(access_key, secret_key)
            )
          end
        end
      end
    end
  end
end
