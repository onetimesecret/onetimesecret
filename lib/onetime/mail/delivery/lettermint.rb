# lib/onetime/mail/delivery/lettermint.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Delivery
      # Lettermint delivery backend using their email API.
      # Supports text/HTML emails via the lettermint Ruby SDK.
      #
      # Configuration options (via config hash or ENV):
      #   api_token: Lettermint API token (ENV: LETTERMINT_API_TOKEN)
      #   base_url:  Custom API base URL (ENV: LETTERMINT_BASE_URL)
      #   timeout:   Request timeout in seconds
      #
      class Lettermint < Base
        def initialize(config = {})
          require 'lettermint'
          super
          configure_lettermint_defaults!
        end

        def perform_delivery(email)
          msg = client.email
            .from(email[:from])
            .to(email[:to])
            .subject(email[:subject])
            .text(email[:text_body])
            .html(email[:html_body])

          msg.reply_to(email[:reply_to]) if email[:reply_to] && !email[:reply_to].empty?

          msg.deliver
        end

        # Classify Lettermint SDK errors by type and HTTP status code.
        # TimeoutError is always transient. HttpRequestError uses status
        # codes: 429/5xx are transient, 4xx are fatal. ValidationError
        # and ClientError are fatal (bad input, not retryable).
        def classify_error(error)
          case error
          when ::Lettermint::TimeoutError
            :transient
          when ::Lettermint::ValidationError,
               ::Lettermint::ClientError
            :fatal
          when ::Lettermint::HttpRequestError
            return :transient if error.status_code == 429
            return :transient if error.status_code.between?(500, 599)

            :fatal
          else
            super
          end
        end

        protected

        def validate_config!
          raise ArgumentError, 'Lettermint API token must be configured' if api_token.nil? || api_token.empty?
        end

        private

        def configure_lettermint_defaults!
          ::Lettermint.configure do |c|
            c.base_url = config[:base_url] if config[:base_url]
            c.timeout  = config[:timeout] if config[:timeout]
          end
        end

        def client
          @client ||= ::Lettermint::Client.new(api_token: api_token)
        end

        def api_token
          @api_token ||= config[:api_token] || ENV.fetch('LETTERMINT_API_TOKEN', nil)
        end
      end
    end
  end
end
