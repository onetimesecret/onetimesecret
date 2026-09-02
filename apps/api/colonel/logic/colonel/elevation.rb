# apps/api/colonel/logic/colonel/elevation.rb
#
# frozen_string_literal: true

module ColonelAPI
  module Logic
    module Colonel
      # The colonel step-up (sudo) window (#4327).
      #
      # One definition of the window arithmetic, the identity binding and the
      # dual-mode credential check, shared by the three /elevation endpoints and
      # by {ColonelAPI::Logic::DestructiveAction#require_elevation!} — which is
      # what every TIER 1 verb calls. Included into ColonelAPI::Logic::Base, so
      # every colonel logic class HAS these methods; only the elevation
      # endpoints and the tier-1 guard CALL them.
      #
      # ## Where the window lives
      #
      # `sess['elevated_until']`, a REGISTERED session sidecar field
      # (lib/onetime/session/sidecar.rb) holding an OBJECT, not a bare epoch:
      #
      #     { 'extid' => <acting colonel's public id>, 'exp' => <unix seconds> }
      #
      # One onetime.session cookie can outlive an identity change — simple-mode
      # login (apps/web/core/controllers/authentication.rb) neither clears nor
      # renews the session, and full-mode :renew carries the session hash to a
      # new sid — so a bare epoch would let the account signing in second
      # inherit the first account's live elevation. {#elevation_record} ignores
      # a record naming any other extid; both login paths also delete the field
      # outright, so the binding is a backstop rather than the only defence.
      #
      # STRING key on purpose: the auth side uses string keys throughout and
      # base_session_auth_strategy.rb records the bug a symbol key caused.
      #
      # ## Residual risk, stated rather than hidden
      #
      # Elevation is carried by the SESSION. While a window is live, a stolen
      # cookie is exactly as capable as it was before this feature existed. What
      # the window buys is that the capability is time-bounded, operator-
      # initiated and audited instead of standing. Binding it to a value the
      # cookie does not carry (an elevation nonce echoed as a request header) is
      # the follow-up, not this epic.
      module Elevation
        # STRING key — see base_session_auth_strategy.rb:36-38 for the bug a
        # symbol key caused on this side of the session.
        SESSION_KEY = 'elevated_until'

        # 10 minutes: long enough for a multi-step triage session, short enough
        # that an idle console is not a standing destructive capability.
        DEFAULT_WINDOW = 600

        # OFF by default. See #within_reauth_grace? for why a non-zero grace is
        # only ever offered to accounts that cannot satisfy the password factor.
        DEFAULT_REAUTH_GRACE = 0

        # The factors POST /api/colonel/elevation accepts. Which of them a GIVEN
        # account may actually use is #available_factors, not this list.
        FACTORS = %w[password recent_auth].freeze

        def elevation_enabled?
          elevation_config.fetch('enabled', true) != false
        end

        def elevation_window
          value = elevation_config['window'].to_i
          value.positive? ? value : DEFAULT_WINDOW
        end

        # 0 legitimately DISABLES the grace and is the shipped default, so this
        # cannot use the positive_* guard's fall-back-to-default behaviour: a
        # configured 0 must stay 0, not become DEFAULT_REAUTH_GRACE.
        def elevation_reauth_grace
          raw = elevation_config['reauth_grace']
          return DEFAULT_REAUTH_GRACE if raw.nil?

          value = raw.to_i
          value.negative? ? DEFAULT_REAUTH_GRACE : value
        end

        # The stored capability, or nil. Identity-bound: a record naming a
        # different extid is IGNORED, never honoured.
        #
        # Tolerates both shapes the sidecar can hand back — a Hash (the codec
        # round-trips JSON objects natively) and a JSON string (a plaintext or
        # pre-decode read) — and treats anything else, including the bare epoch
        # an earlier draft would have written, as no elevation at all.
        def elevation_record
          raw = sess && sess[SESSION_KEY]
          raw = Familia::JsonSerializer.parse(raw) if raw.is_a?(String) && raw.start_with?('{')
          return nil unless raw.is_a?(Hash)

          holder = raw['extid'].to_s
          return nil if holder.empty? || holder != cust&.extid.to_s

          raw
        rescue StandardError
          nil
        end

        def elevated_until
          elevation_record&.fetch('exp', 0).to_i
        end

        def elevated?
          elevated_until > Familia.now.to_i
        end

        def elevation_seconds_remaining
          [elevated_until - Familia.now.to_i, 0].max
        end

        # Within the grace window the caller has just proven their primary
        # credential at sign-in, so re-proving it adds nothing.
        #
        # Available ONLY to accounts that cannot satisfy the password factor,
        # and only when an operator configured a non-zero grace. Handing it to
        # password holders would make step-up a no-op for the first N seconds
        # after every colonel sign-in — verbatim the condition #4327 exists to
        # remove, and reachable by a cookie thief because cookie theft happens
        # while the operator is working.
        def within_reauth_grace?
          grace = elevation_reauth_grace
          return false unless grace.positive?
          return false if elevation_password_available?

          stamped = sess && sess['authenticated_at'].to_i
          return false unless stamped.to_i.positive?

          (Familia.now.to_i - stamped.to_i) <= grace
        end

        # The factors THIS account may use, not the constant list: it is what
        # lets the console render an actionable remediation instead of looping
        # on a prompt the operator cannot satisfy.
        def available_factors
          factors = ['password']
          factors << 'recent_auth' if elevation_reauth_grace.positive? && !elevation_password_available?
          factors
        end

        def grant_elevation!
          sess[SESSION_KEY] = {
            'extid' => cust.extid.to_s,
            'exp' => Familia.now.to_i + elevation_window,
          }
        end

        def drop_elevation!
          sess.delete(SESSION_KEY)
        end

        # Dual-mode password verification. MUST branch on full_enabled? BEFORE
        # naming Auth::Config: registry.rb drops the whole apps/web/auth tree in
        # simple mode, so the constant does not exist there. Copied from
        # apps/api/account/logic/account/update_password.rb.
        def verify_elevation_password(password)
          return false if password.to_s.empty?

          if Onetime.auth_config.full_enabled?
            verify_elevation_password_full_mode(password)
          else
            cust.passphrase?(password)
          end
        end

        def verify_elevation_password_full_mode(password)
          Auth::Config.valid_login_and_password?(login: cust.email, password: password)
        rescue Rodauth::InternalRequestError => ex
          OT.le('[colonel-elevate] Rodauth verification failed', exception: ex)
          false
        rescue StandardError => ex
          OT.le('[colonel-elevate] password verification error', exception: ex)
          false
        end

        # Can this account satisfy the password factor?
        #
        # Gates the recent_auth factor: the grace exists so password-LESS
        # operators can elevate at all, not so password holders can skip
        # re-entry. FAIL CLOSED — an unknown answer counts as "has a password",
        # which REFUSES recent_auth rather than granting it, mirroring
        # features/mfa.rb's account_has_challengeable_password?(error_result: true).
        #
        # Full mode answers a flat `true` by design, not by omission. The
        # Rodauth-side probe needs `db[password_hash_table]` scoped to the
        # account row, which only exists inside a Rodauth instance; reaching it
        # from a logic class would mean inventing a second probe, and a wrong
        # one grants the WEAKER factor. So full-mode accounts are treated as
        # password-holding and recent_auth is simply unavailable there. A
        # full-mode SSO-only fleet sets COLONEL_ELEVATION_ENABLED=false instead;
        # this is recorded in the operator guide, not a defect.
        def elevation_password_available?
          return @elevation_password_available if defined?(@elevation_password_available)

          @elevation_password_available = resolve_elevation_password_available
        end

        def elevation_config
          OT.conf.dig('site', 'admin', 'elevation') || {}
        end

        private

        # Memoized by #elevation_password_available? — within_reauth_grace?,
        # available_factors and ElevateSession#process all ask, and in full mode
        # the answer would otherwise be a DB round-trip each time.
        def resolve_elevation_password_available
          return true if cust.respond_to?(:has_passphrase?) && cust.has_passphrase?

          # Fail closed (see the doc block): full mode cannot be probed from
          # here, so its accounts count as password-holding.
          Onetime.auth_config.full_enabled?
        rescue StandardError => ex
          OT.le('[colonel-elevate] password availability probe failed', exception: ex)
          true
        end
      end
    end
  end
end
