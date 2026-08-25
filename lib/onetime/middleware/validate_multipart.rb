# lib/onetime/middleware/validate_multipart.rb
#
# frozen_string_literal: true

require 'json'
require 'rack'
require 'rack/multipart'

module Onetime
  module Middleware
    # ValidateMultipart
    #
    # Front-stop for malformed multipart request bodies (#4283).
    #
    # Rack parses a multipart body the first time ANY consumer calls
    # Rack::Request#POST — and in this stack the first consumer is not the
    # route handler but Otto::Locale::Middleware, which reads req.params on
    # every request to honor ?locale=. That has two bad failure modes for
    # requests whose multipart body is broken:
    #
    #   1. Rack's multipart parser raises (Rack::Multipart::EmptyContentError
    #      for an empty body with no Content-Length,
    #      Rack::Multipart::BoundaryTooLongError when the declared boundary
    #      never appears, EOFError for a body shorter than Content-Length).
    #      The raise happens inside gem middleware, surfaces as a 500, and
    #      Sentry blames the nearest in-app frame — historically
    #      EntitlementPreviewContext#call, which never touches the body at
    #      all (Sentry issues BACKEND-AD, BACKEND-AR).
    #
    #   2. Rack does not raise but quietly parses nothing. A multipart
    #      Content-Type with no boundary parameter makes
    #      Rack::Multipart.parse_multipart return nil, and Rack then falls
    #      back to parsing the raw multipart body as urlencoded — yielding
    #      garbage params. A Content-Length of 0 short-circuits to the same
    #      empty result. Either way the handler sees no fields and V1
    #      /share answers "You did not provide anything to share"
    #      (BACKEND-AH) for what is really a malformed request.
    #
    # Every one of these is a client error, so this middleware answers 400
    # up front instead of letting the break surface downstream as a 500 or
    # a misleading form error:
    #
    #   - multipart Content-Type without a usable boundary parameter → 400
    #   - multipart request with Content-Length: 0 → 400
    #   - body Rack's multipart parser rejects → 400
    #
    # A parseable body is parsed HERE, eagerly, via Rack::Request#POST.
    # That is not extra work: Rack memoizes the result into
    # env['rack.request.form_hash'] / form_pairs keyed against rack.input,
    # so the locale middleware, CSRF protection, and the route handler all
    # read the memoized params without touching the stream again. The
    # input is rewound afterwards for any downstream consumer that reads
    # env['rack.input'] directly.
    #
    # Mounted after NormalizeContentType (which may repair a comma-joined
    # Content-Type) and before Rack::Parser, the session, and everything
    # else that could trigger param parsing.
    class ValidateMultipart
      # The media types Rack::Request#POST hands to the multipart parser
      # (FORM_DATA_MEDIA_TYPES + PARSEABLE_DATA_MEDIA_TYPES). Other
      # multipart/* subtypes are never body-parsed by Rack and pass through.
      MULTIPART_TYPES = %w[
        multipart/form-data
        multipart/related
        multipart/mixed
      ].freeze

      def initialize(app)
        @app    = app
        @logger = Onetime.get_logger('ValidateMultipart')
      end

      def call(env)
        request = Rack::Request.new(env)
        return @app.call(env) unless MULTIPART_TYPES.include?(request.media_type)

        # RFC 2046 §5.1: the boundary parameter is mandatory. Without one
        # Rack cannot multipart-parse and would instead read the raw body
        # as urlencoded data, producing garbage params. parse_boundary also
        # raises for boundary parameters Rack refuses (duplicated, folded
        # whitespace, over 70 chars) — same verdict either way.
        boundary = begin
          Rack::Multipart::Parser.parse_boundary(env['CONTENT_TYPE'])
        rescue StandardError
          nil
        end
        return reject(env, 'Content-Type is missing a valid multipart boundary') if boundary.nil?

        # A zero-length multipart body cannot contain the closing boundary,
        # let alone a form field. Rack short-circuits it to empty params
        # (no raise), which downstream misreads as "no secret provided".
        # Compare via .to_i to mirror Rack::Multipart.parse_multipart, which
        # also treats a malformed Content-Length value as zero — including
        # an empty string, which is truthy but spec-invalid (Rack SPEC
        # requires digits-only when the key is present). A body behind such
        # a header is unreadable through Rack either way, so a 400 here
        # beats silently dropping every field.
        content_length = env['CONTENT_LENGTH']
        return reject(env, 'multipart request body is empty') if content_length && content_length.to_i.zero?

        begin
          # Parse and memoize. EmptyContentError is an EOFError subclass;
          # every other parser/query error Rack classifies as client-caused
          # includes the Rack::BadRequest module.
          request.POST
        rescue EOFError, Rack::BadRequest
          return reject(env, 'multipart request body could not be parsed')
        ensure
          rewind_input(env)
        end

        @app.call(env)
      end

      private

      # The multipart parser consumes rack.input; the parsed params are
      # memoized in env, but a downstream consumer reading the raw stream
      # (or re-parsing under a different request object) must see the body
      # from the start. Rack 3 no longer guarantees rewindability, hence
      # the respond_to? guard.
      def rewind_input(env)
        body = env['rack.input']
        body.rewind if body.respond_to?(:rewind)
      end

      def reject(env, reason)
        @logger.warn 'Rejected malformed multipart request',
          {
            reason: reason,
            path: env['PATH_INFO'],
            method: env['REQUEST_METHOD'],
            content_type: env['CONTENT_TYPE'],
            content_length: env['CONTENT_LENGTH'],
          }

        [
          400,
          { 'Content-Type' => 'application/json' },
          [JSON.generate({ message: "Invalid multipart request: #{reason}" })],
        ]
      end
    end
  end
end
