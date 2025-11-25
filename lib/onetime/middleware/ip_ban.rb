# lib/onetime/middleware/ip_ban.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # IPBan - Middleware to block requests from banned IP addresses
    #
    # This middleware checks if the request's IP address is in the banned IPs list
    # and returns a 403 Forbidden response if it is.
    #
    # Returns JSON for API requests, HTML for browser requests.
    #
    class IPBan
      def initialize(app)
        @app    = app
        @logger = Onetime.get_logger('IPBan')
      end

      def call(env)
        req        = Rack::Request.new(env)
        ip_address = req.ip

        if ip_address && Onetime::BannedIP.banned?(ip_address)
          @logger.warn 'Blocked request from banned IP', {
            ip: ip_address,
            path: env['PATH_INFO'],
            method: env['REQUEST_METHOD'],
          }

          return forbidden_response(env)
        end

        @app.call(env)
      end

      private

      def forbidden_response(env)
        if api_request?(env)
          json_response
        else
          html_response
        end
      end

      def api_request?(env)
        env['PATH_INFO']&.start_with?('/api')
      end

      def json_response
        [
          403,
          { 'Content-Type' => 'application/json' },
          [JSON.generate({ error: 'Forbidden' })],
        ]
      end

      def html_response
        [
          403,
          { 'Content-Type' => 'text/html; charset=utf-8' },
          [html_body],
        ]
      end

      def html_body
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>403 Forbidden</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                  background-color: #f9fafb;
                  color: #374151;
                  margin: 0;
                  padding: 40px 20px;
                  text-align: center;
                }
                .container {
                  max-width: 400px;
                  margin: 0 auto;
                }
                h1 {
                  font-size: 1.5rem;
                  margin-bottom: 0.5rem;
                }
                p {
                  color: #6b7280;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>403 Forbidden</h1>
                <p>Access denied.</p>
              </div>
            </body>
          </html>
        HTML
      end
    end
  end
end
