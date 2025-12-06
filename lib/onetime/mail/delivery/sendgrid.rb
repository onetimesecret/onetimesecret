# lib/onetime/mail/delivery/sendgrid.rb
#
# frozen_string_literal: true

require 'net/http'
require 'json'
require_relative 'base'

module Onetime
  module Mail
    module Delivery
      # SendGrid delivery backend using their v3 API.
      # Supports multipart text/HTML emails.
      #
      # Configuration options (via config hash or ENV):
      #   api_key: SendGrid API key (ENV: SENDGRID_API_KEY)
      #
      # Note: Uses direct HTTP calls instead of sendgrid-ruby gem
      # for simpler dependency management and error handling.
      #
      class SendGrid < Base
        API_ENDPOINT = 'https://api.sendgrid.com/v3/mail/send'

        def deliver(email)
          email = normalize_email(email)

          OT.ld "[sendgrid] Delivering to #{OT::Utils.obscure_email(email[:to])}"

          payload  = build_payload(email)
          response = send_request(payload)

          # SendGrid returns 202 Accepted for successful sends
          unless response.code.to_i >= 200 && response.code.to_i < 300
            error_body = response.body.to_s[0, 500]
            raise "SendGrid API error: #{response.code} #{error_body}"
          end

          log_delivery(email)
          response
        rescue StandardError => ex
          log_error(email, ex)
          raise
        end

        protected

        def validate_config!
          api_key = config[:api_key] || ENV.fetch('SENDGRID_API_KEY', nil)
          raise ArgumentError, 'SendGrid API key must be configured' if api_key.nil? || api_key.empty?
        end

        private

        def build_payload(email)
          content = [
            {
              type: 'text/plain',
              value: email[:text_body],
            },
          ]

          # Add HTML content if present
          if html_content?(email)
            content << {
              type: 'text/html',
              value: email[:html_body],
            }
          end

          payload = {
            personalizations: [
              {
                to: [{ email: email[:to] }],
                subject: email[:subject],
              },
            ],
            from: { email: email[:from] },
            content: content,
          }

          # Add reply-to if present
          if email[:reply_to] && !email[:reply_to].empty?
            payload[:reply_to] = { email: email[:reply_to] }
          end

          payload
        end

        def send_request(payload)
          uri          = URI(API_ENDPOINT)
          http         = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request                  = Net::HTTP::Post.new(uri)
          request['Authorization'] = "Bearer #{api_key}"
          request['Content-Type']  = 'application/json'
          request.body             = payload.to_json

          http.request(request)
        end

        def api_key
          @api_key ||= config[:api_key] || ENV.fetch('SENDGRID_API_KEY', nil)
        end
      end
    end
  end
end
