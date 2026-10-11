# apps/web/auth/operations/audit_tenant_email_domains.rb
#
# frozen_string_literal: true

require 'auth/lib/logging'

module Auth
  module Operations
    # Operator audit, and on request repair, of tenant SSO identities whose
    # account address lies outside every email domain the tenant organization
    # has proven (RISK-2026-10-10-01, #4734).
    #
    # THE PROBLEM
    # -----------
    # Before #4734 a tenant's identity provider could mint a verified account
    # for any address that had no OTS account yet; the allowlist did not help
    # (the tenant sets it, and an empty list is allow-all). The gate added by
    # #4734 runs in before_omniauth_create_account, so it refuses NEW
    # creations only. An identity bound before the gate keeps signing in, and
    # hooks/login.rb records it as `omniauth_tenant_email_domain_unverified`
    # with `outcome: signed_in` — which lists only the accounts that sign in
    # again. This operation walks the identity table instead, so an operator
    # sees every such binding, including the dormant ones.
    #
    # WHAT IT READS
    # -------------
    # The account_identities rows keyed by THIS domain's provider route and the
    # issuer the live callback writes for it (the same derivation as
    # BackfillTenantIssuer, plus SAML: "<domain_id>|<EntityID>"). For each row
    # the account's address is compared with the proven set exactly as the
    # login gate compares it (Organization#owns_email_domain_through?).
    #
    # WHAT UNLINK CHANGES, AND WHAT IT DOES NOT
    # -----------------------------------------
    # `unlink: true` deletes the identity row and nothing else. The account and
    # its Customer stay: the address owner can still claim the account through
    # a canonical-host password reset, and the tenant identity can no longer
    # sign in to it. A later tenant sign-in asserting that address is refused:
    # the account exists, and an unauthenticated tenant callback never links
    # by email (H-3). No Customer verification field is touched; that is the
    # subject of #4735.
    #
    # PROVENANCE GATE (never bypassed for an unlink)
    # ----------------------------------------------
    # For oidc and entra_id the identity key (provider, issuer, uid) is shared
    # by every tenant that names the same IdP, and by the platform surface when
    # the install-wide provider is that IdP. A row under this tenant's issuer
    # may therefore have been bound somewhere else. Only a row whose Customer
    # carries signup_domain_id == this domain's identifier (set once at JIT
    # creation, never rewritten) is unlinked; any other outside row is
    # reported as :skipped_ambiguous_origin for manual review. SAML keys are
    # domain-scoped by construction, but the gate is applied uniformly.
    #
    # Dry-run by default; idempotent; one Result per row, never raising on a
    # per-row problem.
    #
    class AuditTenantEmailDomains
      include Onetime::LoggerMethods

      IDENTITIES_TABLE = :account_identities

      # Statuses an unlink run may leave a row in, for callers that tally.
      STATUSES = [
        :inside, :outside, :would_unlink, :unlinked, :skipped_ambiguous_origin, :skipped_no_account, :error
      ].freeze

      Result = Struct.new(
        :status,
        :account_id,
        :uid,
        :customer_extid,
        :email_obscured,
        :asserted_domain,
        :provider,
        :issuer,
        :organization_extid,
        :message,
        keyword_init: true,
      )

      attr_reader :domain, :organization, :provider, :issuer, :dry_run, :unlink, :sso_enabled

      def sso_enabled?
        @sso_enabled
      end

      # @param domain [Onetime::CustomDomain] the tenant domain whose identities
      #   are audited
      # @param unlink [Boolean] when true, outside rows that pass the provenance
      #   gate are deleted (subject to dry_run)
      # @param dry_run [Boolean] when true (default), writes nothing and reports
      #   what WOULD happen
      def initialize(domain:, unlink: false, dry_run: true)
        @domain  = domain
        @unlink  = unlink
        @dry_run = dry_run
        @db      = Auth::Database.connection
        raise Onetime::Problem, 'Auth database unavailable (simple auth mode?)' unless @db

        @organization = domain.primary_organization
        raise Onetime::Problem, "Domain #{domain.display_domain} has no primary organization" unless @organization

        sso_config = domain.sso_config
        raise Onetime::Problem, "Domain #{domain.display_domain} has no SSO config" unless sso_config

        @provider    = resolve_provider(sso_config)
        @issuer      = resolve_issuer(sso_config)
        @sso_enabled = sso_config.enabled?
      end

      # The identity rows this tenant's callback would match: provider route +
      # issuer, ordered by id for stable, resumable runs.
      #
      # @return [Array<Hash>] Sequel row hashes (symbol keys)
      def candidate_identities
        identities_ds
          .where(provider: provider, issuer: issuer)
          .order(:id)
          .all
      end

      # Classify one row and, when asked and allowed, unlink it.
      #
      #   no accounts row / blank email          -> :skipped_no_account
      #   address inside the proven set          -> :inside
      #   outside, provenance != this domain     -> :skipped_ambiguous_origin
      #   outside, not unlinking                 -> :outside
      #   outside, unlinking, dry run            -> :would_unlink
      #   outside, unlinking, live               -> :unlinked (or :error)
      #
      # @param row [Hash] a candidate row from candidate_identities
      # @return [Result]
      def process_identity(row)
        account_id = row[:account_id]
        uid        = row[:uid]
        email      = account_email(account_id)

        if email.nil?
          return result(
            :skipped_no_account,
            account_id,
            uid,
            nil,
            nil,
            'No accounts row (or no address) for account_id — orphan identity row',
          )
        end

        asserted_domain = email.split('@').last.to_s
        customer        = resolve_customer(account_id)
        obscured        = OT::Utils.obscure_email(email)

        if organization.owns_email_domain_through?(domain, asserted_domain)
          return result(
            :inside,
            account_id,
            uid,
            customer,
            asserted_domain,
            'Address lies inside a domain the organization has proven',
            obscured: obscured,
          )
        end

        unless customer && customer.signup_domain_id.to_s == domain.identifier.to_s
          origin = if customer.nil?
'no customer'
else
(customer.signup_domain_id.to_s.empty? ? 'blank' : 'other domain')
end
          return result(
            :skipped_ambiguous_origin,
            account_id,
            uid,
            customer,
            asserted_domain,
            "Address is outside the proven set but signup_domain_id (#{origin}) does not name this " \
            'domain; the row may have been bound by the platform or another tenant on the same ' \
            'issuer — left untouched for manual review',
            obscured: obscured,
          )
        end

        unless unlink
          return result(
            :outside,
            account_id,
            uid,
            customer,
            asserted_domain,
            'Address is outside every domain the organization has proven (bound before #4734); ' \
            're-run with --unlink to remove the identity',
            obscured: obscured,
          )
        end

        unlink_identity(row, account_id, uid, customer, asserted_domain, obscured)
      end

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

      # The provider column the live tenant callback writes is the platform
      # ROUTE NAME (see BackfillTenantIssuer#resolve_provider).
      def resolve_provider(sso_config)
        provider = sso_config.platform_route_name.to_s
        raise Onetime::Problem, "SSO config for #{domain.display_domain} has no provider route name" if provider.empty?

        provider
      end

      # The issuer half of this tenant's identity key, as resolve_issuer
      # (features/omniauth.rb) writes it at callback time:
      #   oidc     -> sso_config.issuer, byte-exact
      #   entra_id -> https://login.microsoftonline.com/{tenant_id}/v2.0
      #   saml     -> "<domain_id>|<IdP EntityID>" (Saml.tenant_issuer)
      # SAML is eligible here, unlike the issuer backfill: nothing is relabelled,
      # the rows under the tenant's own key are read and, at most, deleted.
      def resolve_issuer(sso_config)
        provider_type = sso_config.provider_type.to_s

        resolved =
          case provider_type
          when 'oidc'
            sso_config.issuer.to_s
          when 'entra_id'
            tenant_id = sso_config.tenant_id.to_s
            raise Onetime::Problem, "Entra SSO config for #{domain.display_domain} has no tenant_id" if tenant_id.empty?

            "https://login.microsoftonline.com/#{tenant_id}/v2.0"
          when 'saml'
            entity_id = sso_config.reveal_saml_field(:idp_entity_id)
            raise Onetime::Problem, "SAML SSO config for #{domain.display_domain} has no IdP EntityID" if entity_id.empty?

            Onetime::SsoProvider::Saml.tenant_issuer(domain.identifier, entity_id)
          else
            raise Onetime::Problem,
              "provider_type '#{provider_type}' has no tenant-scoped issuer; nothing to audit"
          end

        if resolved.to_s.strip.empty?
          raise Onetime::Problem,
            "Could not resolve an issuer for #{domain.display_domain} (provider_type=#{provider_type})"
        end

        resolved
      end

      def process_identity_safely(row)
        process_identity(row)
      rescue StandardError => ex
        OT.le "[AuditTenantEmailDomains] Error processing identity #{row[:id]}: #{ex.message}"
        result(:error, row[:account_id], row[:uid], nil, nil, ex.message)
      end

      def unlink_identity(row, account_id, uid, customer, asserted_domain, obscured)
        if dry_run
          return result(
            :would_unlink,
            account_id,
            uid,
            customer,
            asserted_domain,
            "Would delete identity row #{row[:id]} (account keeps its address and credentials)",
            obscured: obscured,
          )
        end

        deleted = @db.transaction do
          identities_ds.where(id: row[:id], provider: provider, issuer: issuer, uid: uid).delete
        end

        unless deleted == 1
          OT.le "[AuditTenantEmailDomains] Expected to delete 1 row for identity #{row[:id]} " \
                "but deleted #{deleted} (concurrent change?); re-run"
          return result(
            :error,
            account_id,
            uid,
            customer,
            asserted_domain,
            "Unlink affected #{deleted} rows (expected 1) — concurrent change on identity row #{row[:id]}; re-run",
            obscured: obscured,
          )
        end

        Auth::Logging.log_auth_event(
          :omniauth_tenant_identity_unlinked,
          level: :warn,
          domain_id: domain.identifier,
          org_id: organization.objid,
          account_id: account_id,
          customer_extid: customer&.extid,
          provider: provider,
          email: obscured,
          asserted_domain: asserted_domain,
          reason: :email_domain_unverified,
          actor: 'cli',
        )
        OT.info "[AuditTenantEmailDomains] Unlinked identity #{row[:id]} " \
                "(account #{account_id}, #{obscured}) from #{domain.display_domain}"

        result(
          :unlinked,
          account_id,
          uid,
          customer,
          asserted_domain,
          "Deleted identity row #{row[:id]}; the account keeps its address and credentials",
          obscured: obscured,
        )
      end

      # The address on the accounts row: what the gate would have judged, and
      # what the Customer mirror was created from. Nil for an orphan row.
      def account_email(account_id)
        email = @db[:accounts].where(id: account_id).get(:email).to_s.strip.downcase
        email.empty? ? nil : email
      end

      def resolve_customer(account_id)
        extid = @db[:accounts].where(id: account_id).get(:external_id)
        return nil if extid.to_s.empty?

        Onetime::Customer.find_by_extid(extid)
      rescue StandardError => ex
        OT.le "[AuditTenantEmailDomains] Failed to resolve customer for account #{account_id}: #{ex.message}"
        nil
      end

      def result(status, account_id, uid, customer, asserted_domain, message, obscured: nil)
        Result.new(
          status: status,
          account_id: account_id,
          uid: uid,
          customer_extid: customer&.extid,
          email_obscured: obscured,
          asserted_domain: asserted_domain,
          provider: provider,
          issuer: issuer,
          organization_extid: organization.extid,
          message: message,
        )
      end
    end
  end
end
