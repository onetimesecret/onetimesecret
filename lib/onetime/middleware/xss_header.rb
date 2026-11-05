# lib/onetime/middleware/xss_header.rb
#
# frozen_string_literal: true

require 'rack/protection'

module Onetime
  module Middleware
    # XSSHeader - Rack::Protection::XSSHeader with X-XSS-Protection forced to 0.
    #
    # The parent class emits `X-XSS-Protection: 1; mode=block` alongside
    # `X-Content-Type-Options: nosniff`, and its xss_mode option can only vary
    # the `mode=` suffix — it cannot emit `0`. Current guidance (OWASP, MDN) is
    # to send `0` or omit the header: the XSS auditor it once controlled was
    # removed from Chrome/Edge, and in the legacy browsers that still honor it,
    # enabling the filter is an XS-Leaks side channel. `0` explicitly disables
    # the filter where it still exists; nosniff is the load-bearing half and is
    # inherited unchanged.
    #
    # Enabled via site.middleware.xss_header
    # (ENV: MIDDLEWARE_XSS_HEADER, default: true).
    class XSSHeader < Rack::Protection::XSSHeader
      def call(env)
        status, headers, body               = @app.call(env)
        headers['x-xss-protection']       ||= '0'       if html? headers
        headers['x-content-type-options'] ||= 'nosniff' if options[:nosniff]
        [status, headers, body]
      end
    end
  end
end
