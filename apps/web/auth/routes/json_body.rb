# apps/web/auth/routes/json_body.rb
#
# frozen_string_literal: true

require 'json'

module Auth
  module Routes
    # JSON body parsing for the HAND-ROLLED Roda routes in this directory.
    #
    # Rodauth's json feature parses request bodies only for its OWN routes, so the
    # custom routes here (link_sso, sso_link_confirm) have to parse the body
    # themselves. Shared so the two SSO-linking endpoints cannot drift apart in how
    # they read a request.
    #
    # Included INTO the route modules (not into Auth::Router directly), so anything
    # that includes a route module — the router, or a route spec's minimal Roda app
    # — picks the helper up with it.
    module JsonBody
      private

      # Extract the named keys from a JSON body (Content-Type application/json),
      # falling back to form/query params ONLY for keys ABSENT from the parsed
      # body. Presence is decided with Hash#key?, not truthiness (PR #3900
      # review): an explicit JSON `false`, `0`, or `null` is a value the caller
      # sent and must win over a form/query param of the same name — `parsed[k]
      # || fallback` would silently re-read the form param and change the
      # request's meaning for any route accepting boolean/numeric JSON fields.
      #
      # Returns a Hash keyed by the given SYMBOLS with string values ('' when
      # absent; an explicit JSON null also stringifies to ''), so callers can
      # treat a missing field and an empty one identically. Rewinds the input so
      # nothing downstream is surprised by a consumed body.
      def json_body_params(request, *keys)
        raw = request.body&.read.to_s
        request.body.rewind if request.body.respond_to?(:rewind)

        parsed = begin
          raw.empty? ? {} : JSON.parse(raw)
        rescue JSON::ParserError
          {}
        end
        parsed = {} unless parsed.is_a?(Hash)

        keys.to_h do |key|
          value = parsed.key?(key.to_s) ? parsed[key.to_s] : request.params[key.to_s]
          [key.to_sym, value.to_s]
        end
      end
    end
  end
end
