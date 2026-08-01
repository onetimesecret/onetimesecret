# lib/onetime/middleware/retry_after_header.rb
#
# frozen_string_literal: true

require_relative '../application/error_correlation'

module Onetime
  module Middleware
    ##
    # RetryAfterHeader
    #
    # Emits the `Retry-After` response header for throttled (429) responses.
    #
    # Every security limiter raises {Onetime::LimitExceeded} carrying
    # `retry_after` seconds, and both routing stacks already put that value in
    # the JSON body — but a body field is invisible to the clients and
    # intermediaries that actually back off: proxies, SDK retry policies,
    # `fetch` wrappers, and monitoring all read the HTTP header (RFC 9110
    # §10.2.3). Without it a throttled caller has no machine-readable cue and
    # typically retries immediately, which is the opposite of what a rate limit
    # is for. (Security audit 2026-07-30, finding #2, residual 2.)
    #
    # ## Why a middleware rather than the error handlers
    #
    # Neither error edge can set a response header where it builds the body:
    #
    # - Otto: `register_error_handler` blocks return a body Hash and nothing
    #   else. Otto::Core::ErrorHandler#handle_expected_error builds the header
    #   hash itself, after the block has returned, and offers no hook into it.
    # - Roda (/auth): the `:error_handler` block *could* set `response[...]`
    #   directly, but then the two stacks would carry two independent
    #   implementations of the same header — exactly the drift
    #   Auth::ErrorTranslator exists to avoid.
    #
    # So the value is stashed into the Rack env by the shared
    # {Onetime::Application::ErrorCorrelation} helper both stacks already call
    # (`ENV_RETRY_AFTER`), and this middleware — mounted once in the universal
    # MiddlewareStack, therefore wrapping Otto and Roda apps alike — turns it
    # into a header. Same cross-frame pattern ErrorCorrelation already uses to
    # hand `error_type` up to RequestLogger.
    #
    # Because the stash is driven by the body's `retry_after` field, this covers
    # EVERY limiter that raises LimitExceeded (Reset/Login/Incoming/
    # InviteToken/Passphrase/Feedback/Dns), not just the reset-request one.
    #
    # ## Scope: 429 only
    #
    # `Retry-After` is also legal on 503 and on 3xx, but the only producer of
    # the env value is LimitExceeded (429). Gating on the status keeps a stale
    # env value — e.g. if a future handler re-used the key — from attaching a
    # back-off hint to an unrelated response.
    #
    # Never overwrites: a route that already set the header itself (see
    # apps/web/auth/routes/link_sso.rb and sso_link_confirm.rb, which rescue
    # LimitExceeded inline and build their own 429) keeps its own value.
    #
    class RetryAfterHeader
      # Rack env key written by ErrorCorrelation.apply. Single definition lives
      # there; aliased here so the reader names the contract it depends on.
      ENV_RETRY_AFTER = Onetime::Application::ErrorCorrelation::ENV_RETRY_AFTER

      # Rack 3 requires lowercase response header names.
      HEADER = 'retry-after'

      # Status this middleware annotates. See "Scope" above.
      THROTTLED_STATUS = 429

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)

        seconds = env[ENV_RETRY_AFTER]
        if status.to_i == THROTTLED_STATUS && seconds.is_a?(Integer) && !seconds.negative? &&
           headers && !header_present?(headers)
          headers[HEADER] = seconds.to_s
        end

        [status, headers, body]
      end

      private

      # Case-insensitive presence check. Roda hands back a Rack::Headers (already
      # case-insensitive), but Otto's error path builds a plain Hash with
      # lowercase keys, and inline route rescues set 'Retry-After' — so the check
      # cannot assume either form.
      def header_present?(headers)
        headers.each_key.any? { |key| key.to_s.casecmp(HEADER).zero? }
      end
    end
  end
end
