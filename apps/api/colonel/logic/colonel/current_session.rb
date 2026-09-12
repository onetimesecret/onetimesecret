# apps/api/colonel/logic/colonel/current_session.rb
#
# frozen_string_literal: true

require 'onetime/models/session_metadata'

module ColonelAPI
  module Logic
    module Colonel
      # The acting colonel's own session identity (#4328).
      #
      # Extracted from {ListCustomerSessions}, which computed it inline, so the
      # console's "this is you" badge and the server-side self-revoke interlocks
      # cannot drift into two different answers.
      #
      # INTERNAL: {#current_session_id} is the raw bearer sid — byte-identical to
      # the `onetime.session` cookie — and must NEVER be serialized. Only the
      # HANDLE crosses the wire, and only the handle is used in the interlock
      # comparisons, so the bearer value never enters a comparison path against
      # attacker-supplied input.
      module CurrentSession
        # The colonel's own plain sid. `safe_session_id` yields a Rack SessionId
        # object whose `#public_id` is the cookie value (== SessionMetadata's
        # session_id); a Hash-backed session (JSON auth, some specs) yields nil.
        #
        # @return [String, nil]
        def current_session_id
          sid = safe_session_id
          return nil if sid.nil?

          sid.respond_to?(:public_id) ? sid.public_id : sid.to_s
        end

        # The same session as the non-bearer handle the sidecar rows expose.
        #
        # @return [String, nil]
        def current_session_handle
          sid = current_session_id
          sid && Onetime::SessionMetadata.handle_for(sid)
        end
      end
    end
  end
end
