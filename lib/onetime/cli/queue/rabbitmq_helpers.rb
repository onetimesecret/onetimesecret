# lib/onetime/cli/queue/rabbitmq_helpers.rb
#
# frozen_string_literal: true

require 'uri'

module Onetime
  module CLI
    module Queue
      # Shared helpers for CLI commands that interact with RabbitMQ.
      #
      # Include this module in any Command class that needs to parse AMQP URLs,
      # build management API URLs, or mask credentials in output.
      module RabbitMQHelpers
        # Parse an AMQP URL into its component parts.
        #
        # Returns a hash with keys: :host, :port, :user, :password, :vhost, :scheme
        def parse_amqp_url(url)
          uri      = URI.parse(url)
          raw_path = uri.path&.sub(%r{^/}, '')
          vhost    = raw_path.nil? || raw_path.empty? ? '/' : raw_path
          {
            host: uri.host || 'localhost',
            port: uri.port || 5672,
            user: uri.user || 'guest',
            password: uri.password || 'guest',
            vhost: vhost,
            scheme: uri.scheme || 'amqp',
          }
        end

        # Base URL for the RabbitMQ Management HTTP API.
        def management_url
          ENV.fetch('RABBITMQ_MANAGEMENT_URL', 'http://localhost:15672')
        end

        # Returns [user, password] extracted from RABBITMQ_URL.
        def management_credentials
          amqp_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
          parsed   = parse_amqp_url(amqp_url)
          [parsed[:user], parsed[:password]]
        end

        # Mask credentials in AMQP URL using URI parsing for robustness.
        # Handles passwords containing special characters like : or @
        def mask_amqp_credentials(url)
          uri = URI.parse(url)
          return url unless uri.userinfo

          masked_uri          = uri.dup
          masked_uri.userinfo = '***:***'
          masked_uri.to_s
        rescue URI::InvalidURIError
          # Fallback for malformed URLs
          url.gsub(%r{//[^@]*@}, '//***:***@')
        end
      end
    end
  end
end
