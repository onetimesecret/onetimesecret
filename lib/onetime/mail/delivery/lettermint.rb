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

        def classify_error(error)
          case error
          when ::Lettermint::TimeoutError
            :transient
          when ::Lettermint::ValidationError, ::Lettermint::ClientError
            :fatal
          when ::Lettermint::HttpRequestError
            error.status_code.between?(500, 599) ? :transient : :fatal
          else
            super
          end
        end

        protected

        def validate_config!
          token = config[:api_token] || ENV.fetch('LETTERMINT_API_TOKEN', nil)
          raise ArgumentError, 'Lettermint API token must be configured' if token.nil? || token.empty?
        end

        private

        def client
          @client ||= ::Lettermint::Client.new(
            api_token: api_token,
            **client_options,
          )
        end

        def api_token
          @api_token ||= config[:api_token] || ENV.fetch('LETTERMINT_API_TOKEN', nil)
        end

        def client_options
          opts            = {}
          opts[:base_url] = config[:base_url] if config[:base_url]
          opts[:timeout]  = config[:timeout] if config[:timeout]
          opts
        end
      end
    end
  end
end
