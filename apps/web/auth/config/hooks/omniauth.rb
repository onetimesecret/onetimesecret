# apps/web/auth/config/hooks/omniauth.rb
#
# frozen_string_literal: true

#
# OmniAuth callback hooks for SSO authentication.
# All hooks are provider-agnostic — they use omniauth_provider/omniauth_email
# from the standard OmniAuth auth hash. Adding new providers requires no
# changes here.
#
# Flow: POST /auth/sso/{provider} → IdP → callback → hooks below → login
# Session sync happens via the standard after_login hook (hooks/login.rb).
#
# See: docs/authentication/omniauth-sso.md (full configuration guide)
# See: features/omniauth.rb (provider registration)
#

require 'auth/account_statuses'

module Auth::Config::Hooks
  module OmniAuth
    # Leading/trailing Unicode whitespace, for trimming IdP claims.
    # String#strip is ASCII-only; [[:space:]] covers NBSP and friends.
    SURROUNDING_SPACE = /\A[[:space:]]+|[[:space:]]+\z/

    # Normalize one raw IdP claim into a trimmed String.
    #
    # Non-String input yields '' (fail closed) — see the omniauth_email doc for
    # why a Hashie::Array claim must not be coerced with to_s.
    #
    # @param value [Object] the raw claim as the IdP supplied it
    # @return [String] trimmed claim, or '' when unusable
    def self.trimmed_claim(value)
      return '' unless value.is_a?(String)

      value.gsub(SURROUNDING_SPACE, '')
    end

    # rubocop:disable Metrics/PerceivedComplexity
    # A long, linear chain of Rodauth hook registrations (mirrors the same
    # inline disable on Hooks::Account.configure). Splitting it would scatter the
    # callback flow across methods and obscure the account_from_omniauth branch
    # order the security model depends on.
    def self.configure(auth)
      # ========================================================================
      # Resolve the SSO email (#3499 / #3478) — one override, every consumer.
      # ========================================================================
      #
      # Some IdPs (notably Microsoft EntraID) omit the standard `email` claim
      # for users without an Exchange mailbox, or when the app registration
      # lacks the email optional claim (#3478). Fall back to the verified
      # mailbox attribute `mail` (extra.raw_info["mail"]) when `info.email` is
      # absent.
      #
      # TRUST TIERS (see #3499): only TIER-1, IdP-verified mailbox claims are
      # consulted:
      #   - info.email             (standard OIDC, verified by the IdP)
      #   - extra.raw_info["mail"] (Exchange mailbox attribute)
      # Mutable TIER-2 identifiers (upn, preferred_username) are intentionally
      # NOT used — Microsoft documents them as mutable and unsafe for identity
      # or authorization, so linking on them is an account-takeover vector. The
      # tripwire specs in spec/integration/full/omniauth_missing_email_spec.rb
      # pin that refusal; they must keep passing.
      #
      # WHY OVERRIDE `omniauth_email` RATHER THAN THE INDIVIDUAL HOOKS:
      # rodauth-omniauth registers :omniauth_new_account through
      # auth_private_methods, which GENERATES a zero-arity
      # `_omniauth_new_account` dispatcher that shadows the gem's own
      # `_omniauth_new_account(login)` helper (features/omniauth.rb:173). So
      # configuring `omniauth_new_account` and calling
      # `_omniauth_new_account(resolved)` inside it raises ArgumentError
      # (given 1, expected 0) on every SSO account creation. Overriding the
      # single accessor instead feeds the resolved value to every consumer —
      # account lookup, account creation, and `omniauth_verify_account?`
      # (features/omniauth.rb:152), which the per-hook approach missed.
      #
      # Returns the resolved claim with SURROUNDING WHITESPACE TRIMMED, or nil
      # when the IdP supplied no tier-1 mailbox.
      #
      # WHY TRIM HERE AND NOT DOWNSTREAM: this accessor is the value Rodauth
      # INSERTS. omniauth_create_account -> omniauth_new_account ->
      # _omniauth_new_account(omniauth_email) builds {login_column =>
      # omniauth_email} and omniauth_save_account inserts it verbatim
      # (rodauth-omniauth 0.6.2 features/omniauth.rb:117-124, 173-174). Our
      # before_omniauth_create_account guard below validates its OWN stripped
      # copy and never writes back, so a padded claim ("  alice@contoso.com  ")
      # sailed past the guard and then violated the accounts.valid_email CHECK
      # (migrations/001_initial.rb:27 — the pattern excludes spaces from BOTH
      # the local part and the domain) => Sequel::CheckConstraintViolation => a
      # 500 on the callback, exactly the frozen-screen failure #3478 exists to
      # prevent. Padded-but-valid addresses do occur from OIDC IdPs, so trimming
      # at the single accessor fixes every consumer at once — including
      # omniauth_verify_account? (features/omniauth.rb:152), which compares the
      # stored account[login_column] against this value and would otherwise
      # never match for a padded claim.
      #
      # ONLY whitespace is removed. Case folding and NFC normalization stay
      # downstream in account_from_omniauth (accounts.email is citext, so the
      # row deliberately preserves the IdP's casing), and structural validation
      # stays in before_omniauth_create_account, so the nil path keeps the
      # existing #3478 error behaviour unchanged.
      #
      # NON-STRING CLAIMS FAIL CLOSED (no to_s). A multi-valued IdP attribute
      # arrives as a Hashie::Array, and `.to_s` on it yields the *inspect* form
      # '["user@contoso.com"]' — which satisfies both the structural guard below
      # AND the valid_email CHECK, so it would be INSERTED as the account's
      # login: a junk, unreachable account created silently on a 302. Only a
      # String is a mailbox claim; anything else resolves to nil and takes the
      # same invalid_email redirect as an absent claim.
      #
      # TRIM IS UNICODE-AWARE, deliberately not String#strip: strip removes only
      # ASCII whitespace and NUL, so an NBSP-padded claim (" a@b.com") is
      # NOT stripped, and NBSP is absent from the CHECK's excluded set — it would
      # pass every guard and be stored verbatim as an undeliverable address whose
      # Customer is keyed on the normalized form. [[:space:]] covers the Unicode
      # class, so the trim matches what the comment claims.
      #
      # String keys are correct for both reads: omniauth_auth is an
      # OmniAuth::AuthHash (a Hashie::Mash), which converts nested hashes on
      # assignment and reads indifferently — a strategy that builds raw_info
      # with symbol keys is still found by raw['mail']. Every writer of
      # env['omniauth.auth'] goes through AuthHash (omniauth strategy.rb
      # auth_hash/callback_phase, and the mock path), and rodauth-omniauth only
      # ever reads it, so a plain symbol-keyed Hash cannot reach here. The
      # invariant is pinned directly in the spec rather than through a callback
      # example — AuthHash normalizes keys before this method ever sees them, so
      # no request-level test can distinguish the two access styles.
      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        def omniauth_email
          info  = omniauth_info || {}
          email = Auth::Config::Hooks::OmniAuth.trimmed_claim(info['email'])
          if email.empty?
            raw   = (omniauth_extra && omniauth_extra['raw_info']) || {}
            email = Auth::Config::Hooks::OmniAuth.trimmed_claim(raw['mail'])
          end
          email.empty? ? nil : email
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition

      # Normalize email for case-insensitive account lookup.
      # Required because:
      # - SQLite (dev/test) uses case-sensitive string comparison
      # - Redis Customer records require exact email match
      # - IdPs may return emails with different casing than stored
      # Uses NFC normalization and :fold for international email addresses.
      auth.account_from_omniauth do
        normalized_email = OT::Utils.normalize_email(omniauth_email)
        provider         = omniauth_provider

        # ────────────────────────────────────────────────────────────────
        # #3840 Phase 2: authenticated identity connect (session BINDS, but only
        # with an account-bound CONNECT INTENT established at initiation)
        # ────────────────────────────────────────────────────────────────
        #
        # CANONICAL PRACTICE: an active session is the authorization to bind a
        # new identity — BUT logged_in? alone is NOT proof of connect intent.
        # Tabs share cookies, so a plain second-tab / shared-browser SSO sign-in
        # arriving on an already-authenticated session must NOT be treated as a
        # connect. We therefore require TWO signals to bind:
        #   1. an authenticated session (session_value), and
        #   2. an account-bound connect intent set during INITIATION — the
        #      omniauth_request_validation_phase hook below writes the sidecar
        #      key sidecar:<sid>:sso_connect_intent = session_value (short TTL,
        #      see SessionSidecar::FIELDS) only when the logged-in caller POSTed
        #      connect=1 (the Connected Identities panel). CSRF/state proves
        #      "this browser initiated a request"; the intent nonce proves
        #      "this browser initiated a CONNECT for THIS account".
        # We consume (atomic GETDEL) the nonce here, and bind ONLY when it
        # matches the CURRENT session account. Absent/expired/mismatched intent
        # → fall through to the email-based branches exactly as an
        # unauthenticated caller would (never silently bind onto the session
        # account — that was the #3840 P1 finding).
        #
        # The IdP email still plays NO role in the bind decision. Matching a
        # connect to an email-LOCATED account is the pre-account-hijacking
        # anti-pattern: an attacker who controls an IdP that emits a victim's
        # email must never be routed to the victim's account. We route by
        # session, so the victim is untouched even if the IdP lies about email.
        #
        # "Already linked elsewhere" cannot occur here: an existing
        # (provider, issuer, uid) row routes the gem to
        # account_from_omniauth_identity (rodauth-omniauth 0.6.2
        # _handle_omniauth_callback), so this hook is reached ONLY for a NEW
        # identity.
        #
        # Evaluated FIRST (before the trusted-provider auto-link and the H-3
        # refusal below): a proven session credential + connect intent outranks
        # the email-only heuristics those branches rely on.
        #
        # Return semantics: the gem sets @account to whatever this block
        # returns, skips create-account (account is present), and
        # create_omniauth_identity binds the (provider, issuer, uid) row to
        # that account's id; login then re-affirms the same session. So we must
        # return the SESSION account row (loaded by id), never nil (nil would
        # fall through to omniauth_create_account and 500 on the unique
        # accounts.email index).
        #
        # SURFACE ISOLATION (the one refusal retained on this path): bind ONLY
        # on the PLATFORM surface (session[:validated_omniauth_domain_id] nil).
        # A tenant callback must not bind a tenant-issuer identity onto a
        # platform-session account — a tenant admin controls their IdP's
        # assertions, so such a binding would hand them a login into the
        # account. Authenticated tenant-surface linking needs org-membership
        # verification and is a deliberate follow-up (see docs / open questions).

        # Consume the account-bound connect intent (atomic GETDEL on its
        # sidecar key), then bind only when the SAME session account that
        # initiated the connect is still the authenticated one.
        #
        # SINGLE-USE, BOUNDED IN TIME (#3859): the nonce lives as a short-TTL
        # sidecar key (sidecar:<sid>:sso_connect_intent, ~5 min — one IdP
        # round-trip), NOT as a field in the session blob. A blob-resident
        # nonce was only ever cleared here, so an ABANDONED connect (user
        # cancels at the IdP, the IdP errors, the tab is closed) left it live
        # for the next callback on the session — even a plain connect=0
        # sign-in — to consume and bind on: exactly the shared-browser bind
        # this nonce exists to prevent. Now an abandoned intent needs no
        # cleanup (the key expires), and the request phase below additionally
        # deletes any dangling intent on the next non-connect SSO initiation,
        # so a plain sign-in can never reach this consume with a stale nonce
        # still live. A miss here means "absent or expired" — default-deny.
        # (Blob copies written by pre-#3859 code are discarded unconsumed.)
        session.delete(:sso_connect_intent)
        intent_account_id  = Onetime::SessionSidecar.consume(session.id&.public_id, 'sso_connect_intent')
        has_connect_intent = logged_in? &&
                             !intent_account_id.nil? &&
                             intent_account_id.to_s == session_value.to_s

        if has_connect_intent
          if session[:validated_omniauth_domain_id]
            # Tenant callback on a platform session → refuse (surface isolation).
            Auth::Logging.log_auth_event(
              :omniauth_identity_connect_refused,
              level: :warn,
              provider: provider,
              reason: 'tenant_surface',
            )
            set_redirect_error_flash 'This identity could not be connected. The connection ' \
                                     'was started on the wrong domain.'
            redirect '/signin?auth_error=identity_connect_conflict'
          end

          # Load the authenticated account by SESSION id (never by email).
          # _account_from_session applies the open-status filter and returns nil
          # exactly when the session account is no longer usable (e.g. closed
          # mid-session) — refuse rather than fall through to a JIT duplicate.
          session_account = _account_from_session
          unless session_account
            Auth::Logging.log_auth_event(
              :omniauth_identity_connect_refused,
              level: :warn,
              provider: provider,
              reason: 'session_account_missing',
            )
            set_redirect_error_flash 'This identity could not be connected to your account.'
            redirect '/signin?auth_error=identity_connect_conflict'
          end

          Auth::Logging.log_auth_event(
            :omniauth_identity_connected,
            level: :warn,
            email: OT::Utils.obscure_email(normalized_email),
            provider: provider,
            issuer: resolved_issuer,
            account_id: session_account[account_id_column],
          )
          next session_account
        elsif logged_in?
          # Logged in but NO valid connect intent: a plain SSO sign-in on an
          # already-authenticated session (second tab, shared browser), or an
          # intent that was set for a DIFFERENT account. Do NOT bind onto the
          # session account — fall through to the email-based branches below and
          # treat this exactly like an unauthenticated caller. Log it: a callback
          # reaching an authenticated session without connect intent is the
          # precise shape of the shared-browser/second-tab hazard the intent
          # nonce defends against, so it is worth observing.
          Auth::Logging.log_auth_event(
            :omniauth_connect_intent_absent,
            level: :info,
            provider: provider,
            had_intent: !intent_account_id.nil?,
          )
        end

        # Not authenticated (or logged-in without connect intent): email is the
        # only signal available, so the email-based branches below apply. Locate
        # an existing account by the SAME normalized email each of them uses.
        existing = _account_from_login(normalized_email)

        # ────────────────────────────────────────────────────────────────
        # #3836: opt-in, per-provider, boot-guarded email-based linking
        # ────────────────────────────────────────────────────────────────
        #
        # The H-3 refusal below is correct for the multi-tenant platform: an
        # attacker controlling an IdP that emits a victim's email must not be
        # able to auto-link to the victim's account. But self-hosted
        # single-tenant operators control BOTH OTS and the IdP, so email IS a
        # trustworthy join key for them — and the refusal locks them out.
        #
        # This is the ONE sanctioned exception to "email may LOCATE, only a
        # credential may BIND": an explicit operator declaration (per-provider
        # *_TRUST_EMAIL_FOR_LINKING or global SSO_TRUST_EMAIL_FOR_LINKING) that
        # the IdP is inside the trust boundary. It is scoped to the PLATFORM
        # (env-configured) path only: session[:validated_omniauth_domain_id] is
        # set by omniauth_tenant.rb ONLY on tenant callbacks, so requiring it to
        # be nil excludes the multi-tenant surface by construction.
        #
        # Returning the located account (not nil, not a redirect) makes
        # rodauth-omniauth's _handle_omniauth_callback treat it as the located
        # account and persist the (provider, uid) row via its own upsert — the
        # intended auto-link. The account was located by the SAME normalized
        # email used by H-3, so no widening of the lookup surface occurs.
        if existing &&
           session[:validated_omniauth_domain_id].nil? &&
           Onetime.auth_config.trust_email_for_linking?(provider)
          Auth::Logging.log_auth_event(
            :omniauth_email_linked_trusted_provider,
            level: :warn,
            email: OT::Utils.obscure_email(normalized_email),
            provider: provider,
          )
          next existing
        end

        if existing
          # SECURITY (H-3): reached ONLY when no account_identities row exists
          # for (provider, uid) — `existing` has never linked THIS identity.
          # Returning it would let create_omniauth_identity link the caller's
          # IdP identity to it and log them in → account takeover (an attacker
          # controlling a provider that emits the victim's email is signed in
          # as the victim). Refuse to auto-link by email; require explicit,
          # authenticated linking from account settings instead.
          #
          # This MUST redirect (halt) — returning nil here would fall through to
          # omniauth_create_account (omniauth_create_account? is true), which
          # inserts a row with the duplicate login and violates the unique
          # accounts.email index → 500. redirect halts the callback so we never
          # reach create_omniauth_identity or omniauth_create_account. The
          # domain-validation hook below also runs only on the CREATE path, so
          # the email-link path would bypass it entirely.
          existing_id = existing[account_id_column]

          # ────────────────────────────────────────────────────────────────
          # #3840 Phase 3: sign-in interstitial for PASSWORD-HOLDING accounts.
          # ────────────────────────────────────────────────────────────────
          #
          # A password-holding account CAN prove ownership without a prior
          # session: re-enter the existing password. Instead of dead-ending at
          # the H-3 refusal, mint a single-use challenge snapshotting this
          # callback's (provider, resolved_issuer, uid, email, account id) and
          # redirect to the interstitial, where the password is collected and
          # verified before the (provider, issuer, uid) row is bound
          # (POST /auth/link-sso, apps/web/auth/routes/link_sso.rb). This still
          # honours "email may LOCATE, only a credential may BIND" — the located
          # account is NOT returned here (no auto-link); the credential is proven
          # at the POST.
          #
          # We CANNOT use rodauth.has_password? here: it reads the SESSION
          # account's hash (account ? account_id : session_value), and this branch
          # is the UNAUTHENTICATED path (session_value nil) — it would always be
          # false. Query the located account's hash directly instead, mirroring
          # Rodauth's own password_hash_ds (base.rb) but scoped to existing_id.
          #
          # SURFACE ISOLATION (critical — this guard is NOT redundant): mint ONLY
          # on the PLATFORM surface (session[:validated_omniauth_domain_id] nil). An
          # UNAUTHENTICATED TENANT SSO callback ALSO reaches this email branch:
          # before_omniauth_callback_route (omniauth_tenant.rb) stamps
          # session[:validated_omniauth_domain_id] on EVERY tenant callback, and an
          # unauthenticated caller is not logged in and has no connect intent — so
          # the connect/refuse branches at the top of this hook are skipped and
          # execution falls through to HERE with the tenant key SET. A tenant admin
          # controls their own IdP and can assert ANY email, so WITHOUT this guard
          # the tenant surface would become an unauthenticated, un-lockable
          # password-guessing oracle against arbitrary PLATFORM accounts, and a
          # successful guess would bind the tenant IdP identity onto the victim's
          # platform account — the exact cross-surface takeover #3849 says must stay
          # refused. So gate the mint on the platform surface, matching the trust
          # branch's guard above (session[:validated_omniauth_domain_id].nil?) and
          # the connect branch's tenant refusal. A tenant callback falls through to
          # the H-3 refusal below (no challenge minted, no :omniauth_link_challenge_
          # issued event). Authenticated tenant-surface linking is a deliberate
          # follow-up (#3849).
          # Mint only on the platform surface AND only when the located account has
          # a password to challenge. account_has_challengeable_password? (below) also
          # covers not-yet-migrated Redis-resident passwords so those accounts get
          # the interstitial instead of the H-3 dead-end; see its doc for why that
          # does not weaken anything. SQL-first short-circuit keeps the migrated
          # common case cheap.
          platform_surface = session[:validated_omniauth_domain_id].nil?
          has_password     = platform_surface &&
                             Auth::Config::Hooks::OmniAuth.account_has_challengeable_password?(
                               db[password_hash_table].where(password_hash_id_column => existing_id),
                               normalized_email,
                               provider,
                             )

          if has_password
            challenge = Onetime::SsoLinkChallenge.issue(
              provider: provider,
              issuer: resolved_issuer,
              uid: omniauth_uid,
              email: normalized_email,
              account_id: existing_id,
            )
            Auth::Logging.log_auth_event(
              :omniauth_link_challenge_issued,
              level: :warn,
              email: OT::Utils.obscure_email(normalized_email),
              provider: provider,
              issuer: resolved_issuer,
            )
            # Redirect to the SPA interstitial route (served by the Vue app),
            # carrying the single-use token as a path segment.
            redirect "/link-sso/#{challenge.token}"
          elsif platform_surface
            # ────────────────────────────────────────────────────────────────
            # #3840 Phase 4: mailbox-proof linking for PASSWORDLESS accounts.
            # ────────────────────────────────────────────────────────────────
            #
            # The located account has NO challengeable password, so Phase 3's
            # password interstitial cannot help — but a passwordless account CAN
            # still prove ownership: control of its on-file mailbox (the SAME proof
            # magic-link/email_auth uses to authenticate). Email a single-use token
            # to the ON-FILE address and bind (provider, issuer, uid) only when the
            # user clicks it (POST /auth/sso-link-confirm, routes/sso_link_confirm.rb).
            #
            # SECURITY: the token proves MAILBOX control, so it travels ONLY via the
            # emailed link — NEVER in this callback redirect. We redirect the browser
            # to a TOKEN-LESS notice; the token reaches only the on-file inbox. A
            # caller who merely completed an SSO round-trip asserting the victim's
            # email therefore cannot self-consume it. Still honours "email may
            # LOCATE, only a demonstrated credential may BIND" — mailbox control is
            # the credential.
            #
            # PLATFORM-ONLY (the elsif guard, NOT redundant): an unauthenticated
            # TENANT callback also reaches this email branch with
            # session[:validated_omniauth_domain_id] SET (has_password is already
            # gated on the platform surface, so it is false here for tenants). A
            # tenant admin controls their IdP and could otherwise trigger link emails
            # to arbitrary platform addresses, so tenant callbacks fall through to the
            # H-3 refusal below (authenticated tenant-surface linking is a follow-up,
            # #3849).
            #
            # TWO email identities here, deliberately NOT interchangeable — DO NOT
            # UNIFY THEM. Both halves are security-load-bearing:
            #   on_file_email (existing[:email], the RAW address of record) is the
            #     DELIVERY target. The mailbox-proof credential must go to the
            #     address WE hold, never to the IdP-asserted string, or the proof
            #     proves nothing.
            #   normalized_email (the token's :email, below) is what the confirm-time
            #     OWNERSHIP RE-CHECK compares against — the check in
            #     operations/confirm_sso_link.rb normalizes the reloaded account email
            #     before the ==. Storing the raw address here would make every legacy
            #     mixed-case row (the rows migrations/007_normalize_customer_emails.rb
            #     exists for) fail that check as a spurious :link_conflict.
            on_file_email = existing[:email]

            # ONE customer load serves BOTH the watermark snapshot and the locale.
            # external_id-first (load_by_extid_or_email), NOT find_by_email: confirm
            # time re-derives the watermark with the SAME external_id-first identifier
            # logic (ConfirmSsoLink#watermark_advanced?), and resolving to a different
            # record than confirm time surfaces as a spurious :link_invalidated with no
            # way forward for the user.
            customer = begin
              custid = existing[:external_id].to_s.empty? ? on_file_email : existing[:external_id]
              Onetime::Customer.load_by_extid_or_email(custid)
            rescue StandardError
              nil
            end

            # ISSUANCE GATE — symmetric with the confirm-time watermark probe.
            #
            # ConfirmSsoLink#watermark_state fails SECURE on an unresolvable Customer:
            # nil → :unreadable → :link_error (409). Confirm re-derives the identifier
            # with the SAME external_id-first logic used above, so a Customer that does
            # not resolve HERE will not resolve THERE either — minting anyway would mail
            # a link that is guaranteed to 409 on every click, forever, with no other way
            # in (this branch is reached only for PASSWORDLESS accounts, so the H-3
            # "sign in with your existing method" recovery does not exist for them).
            #
            # This is not hypothetical: `accounts.email` is citext (case-insensitive
            # compare, case-PRESERVING storage) and migrations/007_normalize_customer_
            # emails.rb is a MANUAL migration that bails on duplicates, so mixed-case
            # rows survive in the field. An external_id-less row stored as
            # 'User@Example.com' probes the Customer email index — whose Redis hash keys
            # ARE case-sensitive (customer.rb:282) and hold only the normalized
            # 'user@example.com' — and misses.
            #
            # Do NOT "fix" this by normalizing the identifier on this side alone: the
            # issue-time and confirm-time identifiers must stay derived identically, or
            # the two sides resolve different records and the drift reappears as a
            # spurious :link_invalidated. Refuse instead — the user gets the actionable
            # H-3 message immediately rather than an unredeemable email — and audit it,
            # because an account row whose Customer cannot be resolved also cannot
            # authenticate app-side (BaseSessionAuthStrategy → CUSTOMER_NOT_FOUND) and
            # needs an operator to reconcile it.
            if customer.nil?
              Auth::Logging.log_auth_event(
                :sso_link_verification_customer_unresolved,
                level: :error,
                email: OT::Utils.obscure_email(on_file_email),
                provider: provider,
                account_id: existing_id,
              )
            else
              # Snapshot the account's credential watermark so ANY later credential
              # change (password set/reset/change stamps Customer#last_password_update
              # via UpdatePasswordMetadata) invalidates this token at consume time.
              # Independent fallback (0) — a failure to read the watermark must not
              # silently default the locale, or vice versa.
              watermark = begin
                customer.last_password_update.to_i
              rescue StandardError
                0
              end

              verification = Onetime::SsoLinkVerification.issue(
                provider: provider,
                issuer: resolved_issuer,
                uid: omniauth_uid,
                # NORMALIZED, not on_file_email — see the do-not-unify note above (the
                # confirm-time ownership re-check compares the normalized form).
                email: normalized_email,
                account_id: existing_id,
                sid: session.id&.public_id,
                password_watermark: watermark,
              )

              locale = begin
                loc = customer.locale
                loc.to_s.strip.empty? ? OT.default_locale : loc
              rescue StandardError
                OT.default_locale
              end

              # Deliver to the ON-FILE address. Auth-critical → fail CLOSED, where
              # "sent" must mean SENT: deliver_sso_link_verification (below) performs
              # the send in a way whose outcome this call site can actually observe,
              # and documents why Publisher's return value cannot answer that. Both
              # shapes of failure — a raise AND a "returned without dispatching
              # anything" — consume the just-issued token and fall through to the H-3
              # refusal, rather than telling the user to check an inbox that got no
              # mail while the token lives out its TTL orphaned.
              link_email = {
                email_address: on_file_email,
                confirm_url: "#{base_url}/sso-link-confirm/#{verification.token}",
                provider: provider,
                baseuri: base_url,
                product_name: OT.conf.dig('site', 'product_name'),
                display_domain: public_display_domain,
                locale: locale,
              }

              delivery_error = nil
              sent           = begin
                Auth::Config::Hooks::OmniAuth.deliver_sso_link_verification(link_email)
              rescue StandardError => ex
                delivery_error = ex.message
                false
              end

              if sent
                Auth::Logging.log_auth_event(
                  :sso_link_verification_issued,
                  level: :warn,
                  email: OT::Utils.obscure_email(on_file_email),
                  provider: provider,
                  issuer: resolved_issuer,
                  account_id: existing_id,
                )
                # TOKEN-LESS informational redirect — the token is only in the email.
                # Halts, so everything below is the NOT-sent path.
                redirect '/signin?auth_notice=link_verification_sent'
              end

              # Not sent — either a raise or a "returned without dispatching
              # anything". One audit event for both shapes.
              Auth::Logging.log_auth_event(
                :sso_link_verification_send_FAILED,
                level: :error,
                email: OT::Utils.obscure_email(on_file_email),
                provider: provider,
                error: delivery_error || 'not dispatched (suppressed, delivery disabled, or nothing sent)',
              )

              # Delivery failed → do not leave an un-notified token live; fall through.
              verification.delete!
            end
          end

          # SSO-only account, tenant surface (or platform mailbox delivery failed,
          # or the account's Customer did not resolve so no redeemable link could
          # be minted) → UNCHANGED H-3 refusal.
          #
          # RECOVERY (Phase 2, shipped): a password-first user who hits this
          # refusal self-resolves by signing in with their password, then
          # connecting the IdP from account settings (Connected Identities) —
          # the authenticated connect branch at the top of this hook binds it.
          # The flash below points them at that path.
          Auth::Logging.log_auth_event(
            :omniauth_link_refused_existing_account,
            level: :warn,
            email: OT::Utils.obscure_email(normalized_email),
            provider: provider,
          )
          set_redirect_error_flash 'An account with this email already exists. ' \
                                   'Sign in with your existing method, then link SSO from account settings.'
          redirect '/signin?auth_error=account_exists_link_required'
        end

        # Genuinely new email → allow JIT create (subject to the domain checks
        # in before_omniauth_create_account below).
        nil
      end

      # ========================================================================
      # JSON Mode Override for OmniAuth — now centralized
      # ========================================================================
      #
      # OmniAuth's `omniauth_prefix` paths are exempted from `only_json? true`
      # by Auth::Config::JsonMode (apps/web/auth/config/json_mode.rb). It is
      # the single owner of the only_json? setter because rodauth's
      # def_auth_value_method REPLACES rather than chains, so any per-hook
      # `only_json?` block here would silently clobber others (e.g., OAuth's).

      # ========================================================================
      # ⚠️  CRITICAL: CSRF Bypass for OmniAuth Routes - DO NOT REMOVE
      # ========================================================================
      #
      # CSRF protection operates at two layers here:
      #
      #   1. Rack::Protection::AuthenticityToken (Rack middleware)
      #      - Configured in: lib/onetime/middleware/security.rb
      #      - Uses 'shrimp' parameter name, stores token in session[:csrf]
      #      - Skipped for /auth/sso/* via allow_if callback
      #
      #   2. Rodauth's route_csrf plugin (application layer)
      #      - Auto-loaded when plugin :rodauth is called
      #      - Uses different token format than Rack::Protection
      #      - Runs during omniauth_request_validation_phase
      #
      # WHY THIS HOOK EXISTS:
      # The default omniauth_request_validation_phase calls `check_csrf if check_csrf?`
      # which invokes route_csrf validation. This FAILS because:
      #   - Rack::Protection is skipped → no token in session[:csrf]
      #   - route_csrf tries to decode nil → "encoded token is not a string"
      #
      # OAuth's state parameter provides CSRF protection for the SSO flow:
      #   1. Request phase: OmniAuth generates random state, stores in session
      #   2. Callback phase: Provider returns state, OmniAuth validates match
      #
      # WHAT HAPPENS IF YOU REMOVE THIS HOOK:
      # SSO login breaks immediately with error:
      #   "Roda::RodaPlugins::RouteCsrf::InvalidToken: encoded token is not a string"
      #
      # See: https://github.com/janko/rodauth-omniauth (request validation docs)
      # See: lib/onetime/middleware/security.rb (Rack::Protection config)
      #
      auth.omniauth_request_validation_phase do
        # ⚠️  DO NOT call check_csrf / check_csrf? here.
        #
        # The default body is `check_csrf if check_csrf?`. Re-introducing it
        # breaks SSO with "encoded token is not a string" (Rack::Protection is
        # skipped for /auth/sso/*, so session[:csrf] is absent and route_csrf
        # decodes nil). OAuth's state parameter provides CSRF protection instead.
        #
        # ────────────────────────────────────────────────────────────────
        # #3840 Phase 2: CAPTURE account-bound CONNECT INTENT (the ONE thing
        # this block may do — it does NOT validate CSRF).
        # ────────────────────────────────────────────────────────────────
        #
        # This hook runs during the SSO REQUEST phase (POST /auth/sso/:provider),
        # BEFORE the redirect to the IdP — verified in rodauth-omniauth 0.6.2 /
        # omniauth 2.1.4 (strategy.rb request_call:240 and mock_request_call:325
        # both call request_validation_phase, and it runs inside omniauth_run's
        # set_omniauth_session so `session` is the Rodauth session). It has access
        # to request.params and session.
        #
        # The Connected Identities panel initiates the connect flow with the form
        # field connect=1; a plain sign-in does NOT send it. When a LOGGED-IN
        # caller initiates a connect, stash an ACCOUNT-BOUND intent nonce (the
        # session account id, not a bare boolean) so the callback can verify the
        # SAME account that initiated is the one being bound. The callback
        # (account_from_omniauth) consumes and deletes it.
        #
        # WHY THIS EXISTS (security): logged_in? alone is NOT connect intent.
        # Tabs share cookies, so without this an ordinary second-tab / shared-
        # browser SSO sign-in arriving on an already-authenticated session would
        # be routed through the bind path and permanently attach the arriving IdP
        # identity to the session account. CSRF/state proves "this browser
        # initiated a request"; this nonce proves "this browser initiated a
        # CONNECT for THIS account".
        #
        # SINGLE-USE (#3859): the nonce is a SHORT-TTL SIDECAR KEY
        # (sidecar:<sid>:sso_connect_intent, ~5 min — one IdP round-trip; see
        # SessionSidecar::FIELDS), not a session-blob field, so an abandoned
        # connect needs no cleanup — the key expires whatever the browser does
        # next. The else branch closes the residual in-TTL window: every SSO
        # callback's flow passes through this request phase first (it mints the
        # state the callback validates), so deleting on a non-connect initiation
        # deterministically kills a nonce left dangling by an abandoned connect
        # before a plain (connect=0) callback could consume it. A failed write
        # fails closed: no intent → the callback never binds.
        if logged_in? && request.params['connect'].to_s == '1'
          Onetime::SessionSidecar.write(session.id&.public_id, 'sso_connect_intent', session_value)
        else
          Onetime::SessionSidecar.delete(session.id&.public_id, 'sso_connect_intent')
        end
      end

      # NOTE: before_omniauth_callback_route is OWNED by omniauth_tenant.rb
      # (hooks don't chain; a second definition here would be clobbered — or
      # worse, clobber the tenant validation). The :omniauth_callback_start
      # logging that used to live here moved into that hook.

      # ========================================================================
      # HOOK: Before OmniAuth Account Creation - Domain Validation
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires BEFORE Rodauth creates a new account for an SSO user.
      # Used to enforce domain restrictions for SSO signups.
      #
      # RESOLUTION ORDER:
      # 1. Per-domain SignupConfig (if custom domain and config enabled)
      # 2. Global allowed_signup_domains config (fallback)
      #
      # CONFIGURATION:
      # Per-domain: Configure via CustomDomain::SignupConfig
      # Global: Set via ALLOWED_SIGNUP_DOMAIN environment variable (comma-separated)
      #
      auth.before_omniauth_create_account do
        email = omniauth_email.to_s.strip.downcase

        # Reject unusable emails from IdP (distinct from policy rejection): a
        # missing/empty claim, or any shape the accounts.valid_email CHECK
        # constraint would reject (internal spaces, comma/semicolon in either
        # part, a dotless domain, etc. — see SignupValidation::VALID_EMAIL_PATTERN).
        # Redirect with a stable error code so Login.vue can show a localized
        # message — matches the email_auth/omniauth_on_failure convention.
        # Inline JSON via throw_error_status was clobbered by omniauth_on_failure,
        # collapsing the specific code into the generic sso_failed. Failing here
        # (rather than letting a claim the CHECK rejects fall through to account
        # creation, which 500s as Sequel::CheckConstraintViolation) keeps the
        # user on a localized error instead of a frozen screen (#3478, #3971).
        unless Onetime::SignupValidation.structurally_valid_email?(email)
          Auth::Logging.log_auth_event(
            :omniauth_invalid_email,
            level: :warn,
            email: OT::Utils.obscure_email(email),
            provider: omniauth_provider,
          )
          redirect '/signin?auth_error=invalid_email'
        end

        # Get display_domain from DomainStrategy middleware (already in env)
        display_domain = request.env['onetime.display_domain']

        # Use shared validation module for per-domain + global fallback
        unless Onetime::SignupValidation.valid_signup_email?(email, display_domain: display_domain)
          Auth::Logging.log_auth_event(
            :omniauth_domain_rejected,
            level: :warn,
            email: OT::Utils.obscure_email(email),
            domain: email.split('@').last,
            display_domain: display_domain,
            provider: omniauth_provider,
          )
          # Generic error code — don't reveal which domains are allowed.
          redirect '/signin?auth_error=domain_not_allowed'
        end

        Auth::Logging.log_auth_event(
          :omniauth_domain_validated,
          level: :debug,
          email: OT::Utils.obscure_email(email),
          display_domain: display_domain,
          provider: omniauth_provider,
        )
      end

      # ========================================================================
      # HOOK: After OmniAuth Account Creation
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires after Rodauth creates a new account for an SSO user.
      # Similar to after_create_account, but specific to OmniAuth flow.
      #
      auth.after_omniauth_create_account do
        Auth::Logging.log_auth_event(
          :omniauth_account_created,
          level: :info,
          account_id: account_id,
          email: OT::Utils.obscure_email(account[:email]),
          provider: omniauth_provider,
        )

        # Capture the signup domain so it can be set on the new Customer in a
        # single write (instead of save-then-update). Lookup is cheap and pure;
        # leave it outside safe_execute so failures still surface.
        display_domain   = request.env['onetime.display_domain']
        custom_domain    = display_domain ? Onetime::CustomDomain.load_by_display_domain(display_domain) : nil
        signup_domain_id = custom_domain&.identifier

        # ────────────────────────────────────────────────────────────────
        # Verified state for the JIT-provisioned Customer (#3973)
        # ────────────────────────────────────────────────────────────────
        #
        # CreateCustomer defaults to verified: false because that is the
        # PASSWORD signup shape — Rodauth's after_verify_account flips the flag
        # when the emailed link is followed. A JIT SSO account never traverses
        # that flow, so the Customer mirror stayed unverified forever while its
        # Rodauth account was already open. That is not cosmetic:
        # has_system_role? (authorization_policies.rb) returns false on
        # `!cust.verified?` BEFORE it reads the role field, so an
        # SSO-provisioned colonel could never exercise the role even after CLI
        # promotion.
        #
        # THE GATE — all three must hold, and nothing else is consulted:
        #
        #   1. We are inside after_omniauth_create_account. This hook fires
        #      only on SSO JIT provisioning (the same call that stamps
        #      provisioning_origin: 'sso_jit'), never on password signup and
        #      never on login.
        #   2. Rodauth has ALREADY persisted this account at
        #      AccountStatuses::VERIFIED. rodauth-omniauth 0.6.2 stamps
        #      account_open_status_value in _omniauth_new_account and commits it
        #      in omniauth_save_account, both of which run BEFORE this hook
        #      (omniauth_create_account), so the read below reports the auth
        #      store's own decision rather than making a new one. If a
        #      deployment opens SSO accounts unverified (or skip_status_checks?
        #      is on) the read is not VERIFIED and the Customer stays
        #      unverified — exactly the pre-fix behaviour.
        #   3. The IdP did not EXPLICITLY assert email_verified: false.
        #
        # This only mirrors an auth-store fact onto the Customer record; it
        # grants nothing the accounts row does not already grant. It also
        # cannot reach a non-SSO account, which is why there is deliberately NO
        # login-path reconcile: on login a bare status check is worthless
        # because with verify_account disabled every ordinary password account
        # is VERIFIED too. Records that already drifted are handled by
        # `bin/ots customers doctor --repair` (:sso_customer_unverified).
        account_status = db[:accounts].where(id: account_id).get(:status_id)
        sso_verified   = account_status == Auth::AccountStatuses::VERIFIED &&
                         !Auth::Config::Hooks::OmniAuth.idp_asserts_unverified_email?(
                           info: omniauth_info,
                           extra: omniauth_extra,
                         )

        # Create Customer record (same as regular signup)
        customer = Onetime::ErrorHandler.safe_execute(
          'create_customer_omniauth',
          account_id: account_id,
          provider: omniauth_provider,
        ) do
          Auth::Operations::CreateCustomer.new(
            account_id: account_id,
            account: account,
            db: db,
            provisioning_origin: 'sso_jit',
            signup_domain_id: signup_domain_id,
            verified: sso_verified,
            verified_by: sso_verified ? 'sso' : nil,
          ).call
        end

        # Organization assignment for new SSO accounts.
        #
        # MUTUALLY EXCLUSIVE paths — tenant SSO users join the tenant org,
        # canonical SSO users get a default workspace. Never both.
        #
        # Consuming domain_id via session.delete ensures after_login sees nil
        # and skips for new accounts — preventing a redundant idempotent call.
        if customer.is_a?(Onetime::Customer)
          domain_id = session.delete(:validated_omniauth_domain_id)

          if domain_id
            # Tenant domain SSO → join the domain's organization only
            Onetime::ErrorHandler.safe_execute(
              'join_domain_organization_omniauth',
              external_id: customer.extid,
              domain_id: domain_id,
            ) do
              Auth::Operations::JoinDomainOrganization.new(
                customer: customer,
                domain_id: domain_id,
              ).call
            end

            # IMPORTANT: Do NOT create a fallback workspace here.
            #
            # If JoinDomainOrganization failed, the user authenticated via
            # tenant-domain SSO to join a *specific* organization. Creating
            # an unrelated personal workspace would:
            #   1. Leave them outside the org they intended to join
            #   2. Give them a full account with no org affiliation
            #   3. Bury the join failure — no one investigates
            #
            # The correct response is to fail visibly so the org admin
            # and ops can diagnose why the join didn't stick.
            if customer.organization_instances.to_a.empty?
              OT.le '[omniauth] CRITICAL: Tenant SSO join produced no org membership ' \
                    "for #{customer.external_identifier} (domain_id=#{domain_id}). Orphaned account — admin must investigate."
              redirect '/signin?auth_error=org_join_failed'
            end
          else
            # Canonical domain SSO → create default workspace
            Onetime::ErrorHandler.safe_execute(
              'create_default_workspace_omniauth',
              external_id: customer.extid,
            ) do
              Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
            end
          end
        end
      end

      # ========================================================================
      # Failure Configuration
      # ========================================================================
      #
      # Configure flash message and redirect for authentication failures.
      # The default omniauth_on_failure method handles the actual failure flow.
      #
      auth.omniauth_failure_error_flash 'SSO authentication failed. Please try again or use password login.'

      # ========================================================================
      # HOOK: OmniAuth Failure Handler
      # ========================================================================
      #
      # Override to add debug logging before redirecting on failure.
      # The omniauth_error_type and omniauth_error are populated by rodauth-omniauth
      # from OmniAuth's env['omniauth.error.type'] and env['omniauth.error'].
      #
      auth.omniauth_on_failure do
        # Extract error details with safe fallbacks for logging.
        # Use safe navigation and || fallbacks to avoid exceptions.
        error_type  = (omniauth_error_type if respond_to?(:omniauth_error_type)) || :unknown
        error_msg   = omniauth_error&.message || 'No error message'
        error_class = omniauth_error&.class&.name || 'Unknown'

        # Debug: write to stderr so it shows in overmind/terminal
        warn "[OmniAuth FAILURE] type=#{error_type} class=#{error_class} msg=#{error_msg} path=#{request.path}"

        Auth::Logging.log_auth_event(
          :omniauth_failure,
          level: :warn,
          error_type: error_type,
          error_message: error_msg,
          path: request.path,
          ip: request.ip,
        )

        redirect omniauth_failure_redirect
      end

      auth.omniauth_failure_redirect do
        # Redirect to Vue frontend login page with error indicator.
        # Query param allows frontend to display appropriate error message.
        #
        # A user clicking "Cancel"/"Deny" at the IdP arrives here as OAuth2
        # error=access_denied (OmniAuth surfaces it as the failure type).
        # That's a choice, not a malfunction — route it to its own code so
        # the frontend can render calm "sign-in was cancelled" copy instead
        # of the alarming generic failure message.
        error_type = (omniauth_error_type if respond_to?(:omniauth_error_type)) || :unknown
        if error_type.to_s == 'access_denied'
          '/signin?auth_error=sso_cancelled'
        else
          '/signin?auth_error=sso_failed'
        end
      end
    end
    # rubocop:enable Metrics/PerceivedComplexity

    # Did the IdP EXPLICITLY tell us the address is not verified?
    #
    # Only an explicit false is a veto. Absence is NOT: the claim is an OIDC
    # optional, and several supported providers (Entra ID, plain OAuth2
    # strategies, GitHub) never emit it at all — treating silence as
    # "unverified" would leave those deployments in exactly the broken state
    # the caller is fixing, while treating it as a positive signal would be us
    # inventing an assertion the IdP never made. So this narrows the
    # verified stamp and can never widen it.
    #
    # Looks in `info` first, then `extra.raw_info` (OIDC UserInfo / the decoded
    # id_token). Both may be a plain Hash or an OmniAuth::AuthHash, and may be
    # string- or symbol-keyed, so every read goes through fetch_claim.
    #
    # @param info [Hash, OmniAuth::AuthHash, nil] omniauth_info
    # @param extra [Hash, OmniAuth::AuthHash, nil] omniauth_extra
    # @return [Boolean] true only on an explicit false-y assertion
    def self.idp_asserts_unverified_email?(info:, extra:)
      claim = fetch_claim(info, 'email_verified')
      claim = fetch_claim(fetch_claim(extra, 'raw_info'), 'email_verified') if claim.nil?
      return false if claim.nil?

      # Some providers stringify the claim ("false"); false and "false" are the
      # same assertion. Anything else (true, "true", 1, garbage) is not a veto.
      claim.to_s.strip.downcase == 'false'
    end

    # Key-shape-tolerant single-key read. Returns nil for a missing key, an
    # unindexable source, or any error — never raises into a callback.
    #
    # @param source [#[], nil]
    # @param key [String] string key; the symbol form is tried as a fallback
    # @return [Object, nil]
    def self.fetch_claim(source, key)
      return nil unless source.respond_to?(:[])

      value = source[key]
      value = source[key.to_sym] if value.nil?
      value
    rescue StandardError
      nil
    end

    # Does the located account have a password the Phase 3 interstitial can
    # challenge? True when a Rodauth password hash exists, OR (coverage) when a
    # password still resident in Redis under the simple->full migration
    # (config/overrides/password_migration.rb) has not yet been written to
    # account_password_hashes. Consulting the migration source keeps those
    # (shrinking, self-healing) accounts on the interstitial instead of the H-3
    # dead-end, and does NOT weaken anything: the bind is still gated on the POST
    # /auth/link-sso password verify, which itself routes through password_match?
    # -> migrate_password_from_redis (the SAME transparent path a normal login
    # uses), and the account was already LOCATED by the caller, so no new
    # existence / has-password oracle is introduced. SQL-first short-circuit
    # avoids the Redis read for the migrated common case. Extracted from
    # account_from_omniauth to keep that hook's branching (and complexity)
    # contained.
    #
    # FAIL DIRECTION on probe error is the CALLER'S call (error_result):
    # - The omniauth interstitial minting (default false) fails SAFE by falling
    #   through to the H-3 refusal — never a weaker bind.
    # - The password-modification gate (features/mfa.rb) passes true: on a
    #   probe outage an account must be TREATED as password-holding, so
    #   modifications stay password-gated (fail closed) rather than silently
    #   exempting a possibly-hijacked session.
    #
    # SHARED with features/mfa.rb's modifications_require_password? gate: a
    # Redis-resident (not-yet-migrated) password must satisfy that gate the
    # same way it satisfies this interstitial — has_password? alone cannot see
    # it (it reads only account_password_hashes).
    #
    # @param hash_ds [Sequel::Dataset] account_password_hashes scoped to the id
    # @param normalized_email [String] email that located the account
    # @param provider [String] provider/context tag (logging only)
    # @param error_result [Boolean] value returned when the probe errors
    # @return [Boolean]
    def self.account_has_challengeable_password?(hash_ds, normalized_email, provider, error_result: false)
      return true if hash_ds.any?

      Onetime::Customer.email_exists?(normalized_email) &&
        !!Onetime::Customer.find_by_email(normalized_email)&.has_passphrase?
    rescue StandardError => ex
      Auth::Logging.log_auth_event(
        :omniauth_link_password_probe_error,
        level: :warn,
        email: OT::Utils.obscure_email(normalized_email),
        provider: provider,
        error: ex.message,
      )
      error_result
    end

    # Send the Phase 4 mailbox-proof link and report whether it was ACTUALLY
    # dispatched.
    #
    # The obvious call — Publisher.enqueue_email(..., fallback: :sync) — CANNOT
    # answer that question, and this is the one send in the app where a wrong
    # answer strands the user: the callback redirects them to "check your inbox"
    # while the only credential that completes the link never arrives, and the
    # token lives out its TTL orphaned. Publisher returns true when QUEUED and
    # false when the fallback ran, and execute_fallback DISCARDS
    # send_synchronously's boolean (lib/onetime/jobs/publisher.rb:551-553), which
    # itself swallows Onetime::Mail::DeliveryError by contract (publisher.rb:595-600,
    # 621-623) — so a REJECTED send is indistinguishable from a queued one. Two
    # further paths are silent successes at the MAIL layer, on the QUEUED route
    # too: a suppressed recipient (Delivery::Base#deliver returns nil,
    # mail/delivery/base.rb:55-58) and EMAILER_MODE=disabled (Delivery::Disabled,
    # mail/delivery/disabled.rb:21-23).
    #
    # So this auth-critical call site does the send itself:
    #   1. probe the two silent-drop conditions BEFORE claiming anything;
    #   2. hand the message to RabbitMQ with fallback: :none, so a true return
    #      means genuinely QUEUED and never "fell back to something I cannot
    #      see" — the queued happy path stays non-blocking for the callback;
    #   3. when nothing was queued (jobs disabled, RabbitMQ down), deliver INLINE
    #      through the same mail path the worker uses, where a nil return (nothing
    #      dispatched) and a raised DeliveryError are both visible to us.
    #
    # NOT fallback: :raise — that refuses to deliver at all when RabbitMQ is down,
    # turning a degraded-but-working install into a broken one. Publisher's own
    # semantics are deliberately left ALONE: every other mailer in the app shares
    # them and none of them are auth-critical in this way.
    #
    # @param data [Hash] :sso_link_verification template data (email_address,
    #   confirm_url, provider, locale, ...)
    # @return [Boolean] true only when queued or observably dispatched
    # @raise [StandardError] transport/delivery errors from the inline path; the
    #   caller audits them and fails closed
    def self.deliver_sso_link_verification(data)
      require 'onetime/mail'

      recipient = data[:email_address].to_s

      # Silent-drop probe 1: the install has no delivery at all (EMAILER_MODE=
      # disabled/none). Config-only query, no backend instantiated.
      return false if %w[disabled none].include?(Onetime::Mail::Mailer.determine_provider.to_s)

      # Silent-drop probe 2: the recipient is suppressed, so every send to it is
      # skipped — including the queued one, which could never report back here.
      # FAIL-OPEN on a probe error, matching the mail layer's own guard contract
      # (mail/delivery/base.rb:133-141): a suppression-check failure must never
      # block a send. The real send re-runs the same guard.
      suppressed = begin
        defined?(Onetime::EmailSuppression) && Onetime::EmailSuppression.suppressed?(recipient)
      rescue StandardError => ex
        OT.le "[sso-link] suppression probe failed (failing open): #{ex.message}"
        false
      end
      return false if suppressed

      # Queued delivery is the happy path: non-blocking for the callback, and the
      # worker owns retry/DLQ from there.
      return true if Onetime::Jobs::Publisher.enqueue_email(:sso_link_verification, data, fallback: :none)

      # Nothing queued → deliver here and READ the outcome. nil means the mail
      # layer dispatched nothing; a transport failure raises DeliveryError, which
      # the caller treats as not-sent. Locale is passed the way EmailWorker passes
      # it (jobs/workers/email_worker.rb:156-165) — Publisher's in-process fallback
      # drops it and always renders 'en'.
      locale = data[:locale].to_s.strip
      locale = OT.default_locale if locale.empty?

      !Onetime::Mail.deliver(:sso_link_verification, data, locale: locale).nil?
    end
  end
end
