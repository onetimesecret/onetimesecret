# apps/api/colonel/logic/colonel/session_authority.rb
#
# frozen_string_literal: true

require 'onetime/rodauth_admin'

module ColonelAPI
  module Logic
    module Colonel
      # The session-store dual-authority signal for the colonel session views.
      #
      # Both the sessions console (ListSessions) and the per-customer sessions
      # panel (ListCustomerSessions) read the Familia/Redis session store —
      # the authority in simple auth mode. In full mode Rodauth's
      # `account_active_session_keys` table is the session authority instead,
      # and Rodauth-authenticated users may have no Familia session at all. The
      # main repo deliberately grows no SQL awareness here (rodauth-admin
      # CHARTER §4, seam 2): the views SAY they are non-authoritative in full
      # mode and hand the operator over to the standalone Rodauth Admin via an
      # outbound link when RODAUTH_ADMIN_URL is configured.
      module SessionAuthority
        # @return [Hash] `{ mode:, authoritative:, rodauth_admin_url: }`
        #   `rodauth_admin_url` is nil unless full mode AND the URL is set.
        def session_authority
          full = Onetime.auth_config.full_enabled?
          {
            mode: full ? 'full' : 'simple',
            authoritative: !full,
            rodauth_admin_url: Onetime::RodauthAdmin.console_url,
          }
        end
      end
    end
  end
end
