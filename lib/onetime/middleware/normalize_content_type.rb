# lib/onetime/middleware/normalize_content_type.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # NormalizeContentType
    #
    # Recovers a parseable Content-Type for request body parsing when the
    # client sends a malformed or duplicate Content-Type header.
    #
    # Some HTTP clients (notably the OneTimeSecret PHP client at
    # onetime-api.php) send two Content-Type headers in sequence:
    #
    #     Content-Type: text/html; charset=utf-8
    #     Content-type: application/x-www-form-urlencoded
    #
    # HTTP servers handle duplicate Content-Type values inconsistently:
    # some keep the first, some keep the last, some join with `,`. When
    # an unparseable value (text/html) reaches Rack::Parser, the body is
    # not parsed and downstream params are empty — which surfaces in the
    # V1 API as a misleading 404 "You did not provide anything to share".
    #
    # This middleware runs before Rack::Parser and:
    #
    #   1. If CONTENT_TYPE is a comma-joined list, picks the first member
    #      that is parseable (application/json or
    #      application/x-www-form-urlencoded).
    #
    #   2. For POST/PUT/PATCH with an unparseable CONTENT_TYPE, sniffs a
    #      small prefix of the body. If it unambiguously looks like JSON
    #      or form-urlencoded data, rewrites CONTENT_TYPE to match. The
    #      body is rewound after sniffing so downstream consumers see it
    #      unchanged.
    #
    # Multipart and other recognized body types are left alone.
    class NormalizeContentType
      JSON_TYPE       = 'application/json'
      FORM_TYPE       = 'application/x-www-form-urlencoded'
      PARSEABLE_TYPES = [JSON_TYPE, FORM_TYPE].freeze
      BODY_METHODS    = %w[POST PUT PATCH].freeze
      SNIFF_BYTES     = 256

      # Conservative form-data signature: a token, then `=`. Matches the
      # `key=value&key2=value2` shape without false-positiving on prose
      # or HTML/XML.
      FORM_PREFIX_RE = /\A[A-Za-z_][\w.\-\[\]%+]*=/

      def initialize(app)
        @app = app
      end

      def call(env)
        normalize_joined_content_type(env)
        sniff_body_content_type(env) if BODY_METHODS.include?(env['REQUEST_METHOD'])

        @app.call(env)
      end

      private

      def normalize_joined_content_type(env)
        raw = env['CONTENT_TYPE']
        return unless raw.is_a?(String) && raw.include?(',')

        parts               = raw.split(',').map(&:strip).reject(&:empty?)
        preferred           = parts.find { |part| parseable_type?(part) }
        env['CONTENT_TYPE'] = preferred if preferred
      end

      def sniff_body_content_type(env)
        return if parseable_type?(env['CONTENT_TYPE'])

        body = env['rack.input']
        return unless body.respond_to?(:read) && body.respond_to?(:rewind)

        sample = read_sample(body)
        return if sample.nil? || sample.empty?

        sniffed             = sniff(sample)
        env['CONTENT_TYPE'] = sniffed if sniffed
      end

      def read_sample(body)
        body.rewind if body.respond_to?(:rewind)
        body.read(SNIFF_BYTES)
      ensure
        body.rewind if body.respond_to?(:rewind)
      end

      def sniff(sample)
        stripped = sample.lstrip
        return nil if stripped.empty?

        return JSON_TYPE if stripped.start_with?('{', '[')
        return FORM_TYPE if stripped.match?(FORM_PREFIX_RE)

        nil
      end

      def parseable_type?(value)
        return false unless value.is_a?(String)

        # Compare against the bare media type, ignoring parameters
        # like charset=utf-8.
        media_type = value.split(';', 2).first&.strip&.downcase
        PARSEABLE_TYPES.include?(media_type)
      end
    end
  end
end
