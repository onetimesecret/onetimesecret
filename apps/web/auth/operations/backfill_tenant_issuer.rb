# apps/web/auth/operations/backfill_tenant_issuer.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    # Operator-authoritative, one-time backfill of the `issuer` column on legacy
    # tenant SSO identities (#3840 Phase 1 / #3838 item 5).
    #
    # THE PROBLEM
    # -----------
    # Migration 008 re-keyed account_identities from (provider, uid) to
    # (provider, issuer, uid) and backfilled every pre-existing row to the
    # sentinel issuer '' (empty string, never NULL). `provider` is the SHARED
    # strategy route name ('oidc', 'entra') across every tenant, so issuer is the
    # only discriminator between tenants.
    #
    # The read path (features/omniauth.rb#lookup_identity, "Approach A") lets a
    # PLATFORM callback fall back to the '' row and self-heal it, but a TENANT
    # callback is issuer-EXACT and NEVER touches the '' row — that fallback IS the
    # item-5 takeover. Consequence: a tenant SSO user who existed BEFORE migration
    # 008 has only a (provider, '', uid) row, the tenant callback resolves a real
    # (non-'') issuer, the exact lookup misses, and they are LOCKED OUT
    # (account_from_omniauth finds the account by email and refuses to auto-link).
    #
    # THE FIX (this operation)
    # ------------------------
    # Stamp the authoritative issuer onto those legacy '' rows so the exact tenant
    # lookup matches — the sanctioned, operator-driven alternative to a read-path
    # grace. It NEVER weakens the tenant invariant; it just makes the pre-008 rows
    # look like rows a post-008 tenant login would have written.
    #
    # SECURITY: scoping is per-row and passes TWO fail-closed gates before any
    # write (a blanket "(provider, '') -> issuer" is a cross-tenant takeover
    # because `provider` is shared):
    #
    #   1. DOMAIN-SCOPE gate. The account's active OrganizationMembership must be
    #      permitted to access THIS domain (membership.can_access_domain?(domain)).
    #      One org can host many custom domains, each with its own SsoConfig/issuer;
    #      SSO members are domain-scoped by default (JoinDomainOrganization sets
    #      domain_scope_id = domain.objid unless grant_org_scope?). A plain
    #      organization.member? check ignores that scope and would stamp Domain B's
    #      issuer onto a Domain-A-scoped member's row — a scoped item-5 collision.
    #
    #   2. PROVENANCE gate. customer.signup_domain_id (set once at signup from
    #      custom_domain.identifier, never rewritten) must equal THIS domain's
    #      identifier. Org membership alone cannot tell a tenant-IdP-minted '' row
    #      from a platform-IdP-minted one (same shared route, both issuer=''):
    #      stamping a platform-minted row with the tenant issuer would strip its
    #      '' self-heal and break that user's platform login. A blank/mismatched
    #      signup_domain_id fails closed -> :skipped_ambiguous_origin (operator
    #      follows up manually). provisioning_origin does NOT discriminate (always
    #      'sso_jit' for SSO) and is deliberately not used.
    #
    # Only providers whose resolved issuer is non-'' (oidc, entra_id) can lock a
    # user out. google/github resolve to the '' sentinel, so their legacy '' row
    # still matches the exact lookup — those users are NOT locked out and this
    # operation refuses to run for them.
    #
    # Idempotent, dry-run by default. Mirrors BulkSsoMigration's conventions.
    #
    class BackfillTenantIssuer
      include Onetime::LoggerMethods

      # Sentinel issuer used by migration 008 for all pre-existing rows. Must stay
      # in lockstep with Auth::Config::Features::OmniAuth::ISSUER_SENTINEL.
      ISSUER_SENTINEL = ''

      IDENTITIES_TABLE = :account_identities

      # provider_type values whose live callback resolves a REAL (non-sentinel)
      # issuer, and can therefore lock a pre-008 tenant user out. OAuth2 providers
      # (google, github) resolve to '' — their legacy row already matches.
      ISSUER_BEARING_PROVIDER_TYPES = %w[oidc entra_id].freeze

      Result = Struct.new(
        :status,
        :account_id,
        :uid,
        :customer_extid,
        :email_obscured,
        :provider,
        :issuer,
        :organization_extid,
        :message,
        keyword_init: true,
      )

      attr_reader :domain, :organization, :provider, :issuer, :dry_run, :sso_enabled

      # Whether the domain's SsoConfig is currently enabled. Non-fatal: a disabled
      # config is a legitimate backfill target (operator may be repairing before
      # re-enabling), but callers should surface it so an operator can confirm
      # they meant to backfill an inactive domain.
      def sso_enabled?
        @sso_enabled
      end

      # @param domain [Onetime::CustomDomain] the tenant domain whose legacy SSO
      #   identities are being backfilled.
      # @param issuer [String, nil] operator OVERRIDE for the issuer to stamp.
      #   Needed for Entra, where the live `iss` is
      #   https://login.microsoftonline.com/{tenant_id}/v2.0 and may differ from
      #   any stored field. When present (and non-blank) it wins over the
      #   config-derived value for EVERY provider.
      # @param dry_run [Boolean] when true (default), writes nothing and reports
      #   what WOULD happen.
      def initialize(domain:, issuer: nil, dry_run: true)
        @domain  = domain
        @dry_run = dry_run
        @db      = Auth::Database.connection
        raise Onetime::Problem, 'Auth database unavailable (simple auth mode?)' unless @db

        @organization = domain.primary_organization
        raise Onetime::Problem, "Domain #{domain.display_domain} has no primary organization" unless @organization

        sso_config = domain.sso_config
        raise Onetime::Problem, "Domain #{domain.display_domain} has no SSO config" unless sso_config

        @provider    = resolve_provider(sso_config)
        @issuer      = resolve_issuer(sso_config, issuer)
        @sso_enabled = sso_config.enabled?

        unless @sso_enabled
          OT.li "[BackfillTenantIssuer] WARNING: SSO config for #{domain.display_domain} is DISABLED; " \
                'backfilling identities for an inactive domain.'
        end
      end

      # Enumerate the legacy '' identity rows for this domain's provider. These
      # are the candidates — scoping/conflict decisions happen per row in
      # process_identity. Ordered by id for stable, resumable runs.
      #
      # @return [Array<Hash>] Sequel row hashes (symbol keys)
      def candidate_identities
        identities_ds
          .where(provider: provider, issuer: ISSUER_SENTINEL)
          .order(:id)
          .all
      end

      # Process a single legacy identity row.
      #
      # Decision order (both fail-closed gates run BEFORE any write):
      #   1. No resolvable customer for account_id        -> :skipped_no_customer
      #   2. DOMAIN-SCOPE gate: no active membership scoped to this domain
      #                                                   -> :skipped_out_of_scope
      #   3. PROVENANCE gate: signup_domain_id != this domain's identifier
      #                                                   -> :skipped_ambiguous_origin
      #   4. Conflicting exact (provider, issuer, uid) row:
      #        - same account_id      -> dedupe the stale '' row (:deduped)
      #        - different account_id  -> :error (manual account merge required)
      #   5. Otherwise                                    -> stamp issuer (:stamped)
      #
      # @param row [Hash] a candidate row from candidate_identities
      # @return [Result]
      def process_identity(row)
        account_id = row[:account_id]
        uid        = row[:uid]

        customer = resolve_customer(account_id)
        unless customer
          return result(
            :skipped_no_customer,
            account_id,
            uid,
            nil,
            'No customer resolvable from account_id (orphan identity row)',
          )
        end

        obscured = OT::Utils.obscure_email(customer.email)

        # GATE 1 — domain scope. The account's membership must be active AND
        # permitted to access THIS domain (org-scoped members pass; a member
        # scoped to a DIFFERENT domain in the same org does not). Fail closed on
        # a missing/inactive membership.
        membership = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, customer.objid)
        unless membership&.active? && membership.can_access_domain?(domain)
          return result(
            :skipped_out_of_scope,
            account_id,
            uid,
            customer,
            'No active membership scoped to this domain — left untouched',
            obscured: obscured,
          )
        end

        # GATE 2 — provenance. Only stamp rows minted by THIS domain's tenant IdP.
        # signup_domain_id is captured once from custom_domain.identifier and never
        # rewritten; a blank/mismatched value means the '' row may be platform- (or
        # other-domain-) minted, so stamping would break its self-heal. Fail closed.
        unless customer.signup_domain_id.to_s == domain.identifier.to_s
          return result(
            :skipped_ambiguous_origin,
            account_id,
            uid,
            customer,
            "signup_domain_id (#{customer.signup_domain_id.to_s.empty? ? 'blank' : 'other domain'}) " \
            'does not match this domain — origin ambiguous, left untouched for manual review',
            obscured: obscured,
          )
        end

        exact = identities_ds.first(provider: provider, issuer: issuer, uid: uid)
        if exact
          return dedupe_identity(row, exact, account_id, uid, customer, obscured) if exact[:account_id] == account_id

          return result(
            :error,
            account_id,
            uid,
            customer,
            "Conflict: exact (provider, issuer, uid) row #{exact[:id]} belongs to a DIFFERENT account " \
            "(#{exact[:account_id]}). Two accounts claim the same identity under this issuer; " \
            'manual account merge required — NOT auto-resolved.',
            obscured: obscured,
          )
        end

        stamp_identity(row, account_id, uid, customer, obscured)
      end

      # Iterate every candidate, returning one Result per row. Each mutation is
      # its own transaction, so one row's failure never rolls back prior successes
      # (a re-run is idempotent and recovers).
      #
      # @yield [scanned, total] optional progress callback
      # @return [Array<Result>]
      def call
        rows  = candidate_identities
        total = rows.size

        rows.each_with_index.map do |row, idx|
          yield(idx + 1, total) if block_given?
          process_identity_safely(row)
        end
      end

      private

      def identities_ds
        @db[IDENTITIES_TABLE]
      end

      # The provider column value the live tenant callback writes is the platform
      # ROUTE NAME (omniauth_tenant.rb#inject_tenant_credentials deletes :name, so
      # the strategy keeps its platform-registered route). Not the domain extid.
      def resolve_provider(sso_config)
        provider = sso_config.platform_route_name.to_s
        raise Onetime::Problem, "SSO config for #{domain.display_domain} has no provider route name" if provider.empty?

        provider
      end

      # Resolve the issuer to stamp so it equals what resolve_issuer produces at
      # live callback time:
      #   - override present   -> the override (wins for every provider)
      #   - oidc               -> sso_config.issuer (injected into strategy
      #                           options; resolve_issuer precedence #1). NOT
      #                           normalized — must byte-match the live value.
      #   - entra_id           -> https://login.microsoftonline.com/{tenant_id}/v2.0
      #                           (the validated `iss`; resolve_issuer precedence
      #                           #2 via omniauth_token_issuer). DERIVED — verify
      #                           against IdP metadata before --confirm, or pass
      #                           --issuer.
      #   - google/github      -> resolves to '' at callback, so no lockout;
      #                           refuse (nothing to backfill).
      def resolve_issuer(sso_config, override)
        return override.to_s.strip unless override.to_s.strip.empty?

        provider_type = sso_config.provider_type.to_s
        unless ISSUER_BEARING_PROVIDER_TYPES.include?(provider_type)
          raise Onetime::Problem,
            "provider_type '#{provider_type}' resolves to the '' sentinel issuer at callback time, " \
            'so its legacy identity rows already match the exact lookup — these users are NOT locked ' \
            'out and there is nothing to backfill.'
        end

        resolved =
          case provider_type
          when 'oidc'
            sso_config.issuer.to_s
          when 'entra_id'
            tenant_id = sso_config.tenant_id.to_s
            if tenant_id.empty?
              raise Onetime::Problem,
                "Entra SSO config for #{domain.display_domain} has no tenant_id; pass --issuer explicitly " \
                '(live `iss` is https://login.microsoftonline.com/{tenant_id}/v2.0).'
            end
            "https://login.microsoftonline.com/#{tenant_id}/v2.0"
          end

        if resolved.to_s.strip.empty?
          raise Onetime::Problem,
            "Could not resolve a non-empty issuer for #{domain.display_domain} " \
            "(provider_type=#{provider_type}); pass --issuer explicitly."
        end

        resolved
      end

      def process_identity_safely(row)
        process_identity(row)
      rescue StandardError => ex
        OT.le "[BackfillTenantIssuer] Error processing identity #{row[:id]}: #{ex.message}"
        result(:error, row[:account_id], row[:uid], nil, ex.message)
      end

      # Stamp the resolved issuer onto a legacy '' row. The issuer='' guard in the
      # WHERE makes the write idempotent (a concurrent stamp can't double-apply).
      def stamp_identity(row, account_id, uid, customer, obscured)
        if dry_run
          return result(
            :would_stamp,
            account_id,
            uid,
            customer,
            "Would stamp issuer '#{issuer}' onto legacy identity row #{row[:id]}",
            obscured: obscured,
          )
        end

        updated = @db.transaction do
          identities_ds
            .where(id: row[:id], issuer: ISSUER_SENTINEL)
            .update(issuer: issuer)
        end

        # Scan-to-write race guard: the '' row must have been updated exactly
        # once. Zero means it changed under us (already stamped/deduped) — do NOT
        # report :stamped for a no-op, which would corrupt the audit trail.
        unless updated == 1
          OT.le "[BackfillTenantIssuer] Expected to stamp 1 row for identity #{row[:id]} " \
                "but updated #{updated} (concurrent change?); left untouched — re-run"
          return result(
            :error,
            account_id,
            uid,
            customer,
            "Stamp affected #{updated} rows (expected 1) — concurrent change on identity row #{row[:id]}; re-run",
            obscured: obscured,
          )
        end

        OT.info "[BackfillTenantIssuer] Stamped issuer onto identity #{row[:id]} " \
                "(account #{account_id}, #{obscured}) for #{domain.display_domain}"
        result(
          :stamped,
          account_id,
          uid,
          customer,
          "Stamped issuer '#{issuer}' onto identity row #{row[:id]}",
          obscured: obscured,
        )
      end

      # A user who already re-linked has BOTH an exact (provider, issuer, uid) row
      # and a stale (provider, '', uid) row for the SAME account. Stamping the
      # legacy one would violate the composite unique index — drop the stale
      # duplicate instead; the exact row is authoritative.
      def dedupe_identity(row, exact, account_id, uid, customer, obscured)
        if dry_run
          return result(
            :would_dedupe,
            account_id,
            uid,
            customer,
            "Would drop stale legacy row #{row[:id]}; exact row #{exact[:id]} already carries issuer '#{issuer}'",
            obscured: obscured,
          )
        end

        dropped = false
        @db.transaction do
          # Re-verify the exact row still exists before dropping the '' dup.
          still = identities_ds.first(provider: provider, issuer: issuer, uid: uid)
          next unless still

          identities_ds.where(id: row[:id], issuer: ISSUER_SENTINEL).delete
          dropped = true
        end

        unless dropped
          return result(
            :error,
            account_id,
            uid,
            customer,
            "Exact row for uid vanished mid-operation; legacy row #{row[:id]} left untouched — re-run",
            obscured: obscured,
          )
        end

        OT.info "[BackfillTenantIssuer] Deduped stale legacy identity #{row[:id]} " \
                "(account #{account_id}, #{obscured}); exact row #{exact[:id]} authoritative"
        result(
          :deduped,
          account_id,
          uid,
          customer,
          "Dropped stale '' duplicate row #{row[:id]}; exact row #{exact[:id]} authoritative",
          obscured: obscured,
        )
      end

      # account_identities.account_id -> accounts.id -> accounts.external_id (=
      # customer.extid) -> Customer. Nil when the account row, external_id, or
      # customer is missing (orphan identity).
      def resolve_customer(account_id)
        extid = @db[:accounts].where(id: account_id).get(:external_id)
        return nil if extid.to_s.empty?

        Onetime::Customer.find_by_extid(extid)
      rescue StandardError => ex
        OT.le "[BackfillTenantIssuer] Failed to resolve customer for account #{account_id}: #{ex.message}"
        nil
      end

      def result(status, account_id, uid, customer, message, obscured: nil)
        Result.new(
          status: status,
          account_id: account_id,
          uid: uid,
          customer_extid: customer&.extid,
          email_obscured: obscured || (customer && OT::Utils.obscure_email(customer.email)),
          provider: provider,
          issuer: issuer,
          organization_extid: organization.extid,
          message: message,
        )
      end
    end
  end
end
