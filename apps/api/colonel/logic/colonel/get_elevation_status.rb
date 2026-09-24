# apps/api/colonel/logic/colonel/get_elevation_status.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # GET /api/colonel/elevation — the step-up (sudo) window's status (#4327).
      #
      # A cheap read the console fetches on admin mount, after every
      # elevate/drop, and whenever a tier-1 verb answers 403 elevation_required.
      # It is deliberately NOT polled: TrackMetadata advances last_activity_at on
      # every authenticated request, so a polling banner would make #4331's idle
      # timeout unreachable while an admin tab is open. The countdown between
      # fetches is computed client-side from expires_at.
      #
      # A dedicated endpoint rather than a field on GET /info: GetColonelInfo is
      # pinned to the frozen `colonelInfo` response contract, which this epic
      # does not disturb.
      #
      # Read-only, so NOTHING is audited (CONTRACT 4).
      #
      # `details.factors` is per-ACCOUNT, not the constant list: it is what lets
      # the console say "your account has no password and no grace is configured,
      # ask an administrator to set COLONEL_ELEVATION_REAUTH_GRACE" instead of
      # looping on a prompt the operator cannot satisfy.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class GetElevationStatus < ColonelAPI::Logic::Base
        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          success_data
        end

        def success_data
          live = elevated?

          {
            record: {
              elevated: live,
              expires_at: live ? elevated_until : nil,
              seconds_remaining: elevation_seconds_remaining,
            },
            details: {
              enabled: elevation_enabled?,
              window: elevation_window,
              reauth_grace: elevation_reauth_grace,
              grace_available: within_reauth_grace?,
              password_available: elevation_password_available?,
              factors: available_factors,
            },
          }
        end
      end
    end
  end
end
