# apps/web/auth/config/hooks/password.rb
#
# frozen_string_literal: true

#
# Password lifecycle hooks were CONSOLIDATED into Hooks::Account.
#
# Rodauth hooks do NOT chain — each `auth.<hook> do ... end` overwrites the prior
# definition, and config.rb registers Hooks::Account (line ~80) BEFORE Hooks::Password
# (line ~84). So the copies that used to live here silently WON over Account's
# richer versions, leaving Account's structured audit logging and its
# password-changed security email as dead code (the #3275 hook-collision pattern,
# documented in account.rb).
#
# To fix security finding M-2 (sessions must not survive a password change/reset)
# in ONE place, the after_reset_password_request / after_reset_password /
# after_change_password hooks — including session revocation, password-metadata
# sync, and the password-changed security email — now live entirely in
# Hooks::Account. Keeping duplicates here would re-open the overwrite hazard, so
# this module is intentionally empty.
#
module Auth::Config::Hooks
  module Password
    # config.rb calls Hooks::Password.configure(self); keep the entry point so the
    # registration call stays valid. All password-event logic lives in Hooks::Account.
    def self.configure(_auth)
      # Intentionally empty — see the module comment above.
    end
  end
end
