# apps/api/v2/logic/secrets/base_secret_action.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class BaseSecretAction < V2::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :passphrase,
        :secret_value,
        :kind,
        :ttl,
        :recipient,
        :recipient_safe,
        :greenlighted,
        :receipt,
        :secret,
        :share_domain,
        :custom_domain,
        :payload
      attr_accessor :token

      # Process methods populate instance variables with the values. The
      # raise_concerns and process methods deal with the values in the instance
      # variables only (no more params access).
      def process_params
        # All parameters are passed in the :secret hash (secret[:ttl], etc)
        @payload = params['secret'] || {}
        raise_form_error 'Incorrect payload format' if payload.is_a?(String)

        process_ttl
        process_secret
        process_passphrase
        process_recipient
        process_share_domain
      end

      def raise_concerns
        require_entitlement!('api_access')
        raise_form_error 'Unknown type of secret' if kind.nil?

        validate_recipient
        validate_share_domain
        validate_passphrase
      end

      def process
        create_secret_pair
        handle_success
      end

      def success_data
        {
          success: greenlighted,
          record: {
            receipt: receipt.safe_dump,
            metadata: receipt.safe_dump, # V2 backward-compat alias
            secret: secret.safe_dump,
            share_domain: share_domain, # we return the value, but don't save it
          },
          details: {
            kind: kind,
            recipient: recipient,
            recipient_safe: recipient_safe,
          },
        }
      end

      def form_fields
        {
          share_domain: share_domain,
          secret: secret_value,
          recipient: recipient,
          ttl: ttl,
          kind: kind,
        }
      end

      def redirect_uri
        ['/receipt/', receipt.identifier].join
      end

      protected

      def process_ttl
        @ttl = payload.fetch('ttl', nil)

        # Get configuration options. We can rely on these values existing
        # because that are guaranteed by OT::Config.after_load.
        secret_options = OT.conf.dig('site', 'secret_options') || {
          'default_ttl' => 7.days,
          'ttl_options' => [1.minute, 1.hour, 1.day, 7.days],
        }
        default_ttl    = secret_options['default_ttl']
        ttl_options    = secret_options['ttl_options']

        # Get min/max values safely
        min_ttl = ttl_options.min || 1.minute # Fallback to 1 minute

        # Limit enforcement: fail-open (unlimited) when no billing, else plan limit.
        config_max = ttl_options.max || 30.days
        max_ttl    = if auth_org && auth_org.respond_to?(:limit_for)
                    org_limit = auth_org.limit_for('secret_lifetime')
                    org_limit.positive? ? org_limit : config_max
                  elsif anonymous_user?
                    anonymous_max_ttl(config_max)
                  else
                    config_max
                  end

        # Apply default if nil
        @ttl       = default_ttl || 7.days if ttl.nil?

        # Convert to integer, now that we know it has a value
        @ttl = ttl.to_i

        # Entitlement gate: requests beyond free tier TTL require extended_default_expiration.
        # This runs before clamping so the user gets a clear error with upgrade path
        # instead of a silent clamp.
        free_ttl = free_tier_ttl_ceiling
        if ttl > free_ttl && auth_org && !auth_org.can?('extended_default_expiration')
          require_entitlement!('extended_default_expiration')
        end

        # Absolute safety bound: nothing outlives MAX_TTL (365 days). The
        # real ceilings — plan limit, anonymous cap, config ttl_options —
        # are enforced by the bounds check below; this clamp exists because
        # an unlimited plan resolves limit_for to Infinity and the ladder
        # then has no terminal bound. (A hardcoded 30-day clamp here used
        # to override all of those ceilings; see #4008.)
        safety_max = Onetime::Models::Features::WithEntitlements::MAX_TTL
        @ttl       = safety_max if ttl > safety_max

        # Enforce bounds
        @ttl = min_ttl if ttl < min_ttl
        @ttl = max_ttl if ttl > max_ttl
      end

      # The authenticated free-tier TTL ceiling (14 days).
      #
      # Sole consumer is the loud entitlement gate in process_ttl. The anonymous
      # path does NOT derive from this — it has its own configured ceiling (see
      # anonymous_max_ttl), which on a billing-enabled deployment is additionally
      # bounded by the free-tier limit.
      #
      # @return [Integer] Free-tier TTL ceiling in seconds
      def free_tier_ttl_ceiling
        Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL
      end

      # Anonymous TTL ceiling (2026-07-29 API audit, item 4).
      #
      # Lowest of up to three ceilings:
      #
      #   1. The configured anonymous ceiling
      #      (site.secret_options.ttl_max_anonymous, env TTL_MAX_ANONYMOUS,
      #      default 7 days). Read on every deployment, billing or not — that
      #      is the fix for the original audit finding, where the ceiling was
      #      derived from plan state and so vanished with billing disabled.
      #      Operators may raise it: a self-hosted install on a private network
      #      does not share the hosted service's anonymous-abuse threat model.
      #   2. config ttl_options.max, so an operator who caps durations globally
      #      still wins over a larger anonymous setting.
      #   3. the free-tier secret_lifetime limit, consulted ONLY when billing is
      #      enabled and only when positive. This is what preserves the audit's
      #      invariant (anonymous grant <= authenticated free-tier grant) where
      #      that invariant means something. With billing disabled there are no
      #      plans and no free tier, so there is no tier to invert against and
      #      the term is correctly absent rather than fail-open.
      #
      # This is a silent clamp, not a loud 403/422. The anonymous web UI does
      # not depend on that leniency — usePrivacyOptions.ts derives a ttlCeiling
      # from the secret_options.ttl_max_anonymous bootstrap key and filters
      # over-ceiling durations out of the dropdown, so the browser flow never
      # asks for more than it can have. The clamp remains for non-browser API
      # callers (curl, SDKs, integrations), which can still POST an
      # over-ceiling ttl and today get a shortened secret rather than an
      # error. Turning that into a loud rejection is a v3 contract decision;
      # V2's clamp is deliberately unchanged.
      #
      # @param config_max [Integer] ttl_options.max fallback from config
      # @return [Integer] Maximum TTL in seconds for anonymous callers
      # The rescue below only skips the free-tier term; the configured ceiling
      # still applies. BillingConfig.instance is a Singleton whose initialize
      # parses billing.yaml — so the only way here is a config/boot fault, not a
      # transient datastore blip. Log the exception class so an unreachable or
      # malformed billing config is distinguishable from billing genuinely being
      # disabled, which is otherwise the same silent code path.
      def anonymous_max_ttl(config_max)
        ceilings = [
          Onetime::Models::Features::WithEntitlements.configured_anonymous_max_ttl,
          config_max,
        ]

        billing_enabled = begin
          Onetime::BillingConfig.instance.enabled?
        rescue StandardError => ex
          OT.le "[anonymous_max_ttl] BillingConfig unavailable (#{ex.class}: #{ex.message}); " \
                "anonymous TTL ceiling falls back to #{ceilings.min}"
          false
        end

        if billing_enabled
          free_tier_max = Onetime::Organization.free_tier_limits['secret_lifetime.max'].to_i
          ceilings << free_tier_max if free_tier_max.positive?
        end

        ceilings.min
      end

      def process_secret
        raise NotImplementedError, 'You must implement process_secret'
      end

      # Our passphrase contract: presence determines intent.
      #   - Param key missing → no passphrase protection (nil)
      #   - Param key present → use value as-is (including empty string)
      #
      # We honour exactly what is included with the request without guessing.
      # It's the, "if it fits, I sits" design model.
      #
      # UX concerns (e.g. preventing accidental empty-passphrase secrets) are
      # the client's responsibility. The API layer remains value-neutral.
      def process_passphrase
        @passphrase = payload.key?('passphrase') ? payload['passphrase'].to_s : nil
      end

      # Our recipient contract: always a list of sanitized strings.
      #
      # Sanitization keeps trash out but does not validate as an email address.
      #
      def process_recipient
        # Make sure we're dealing with a list.
        recipient_list  = [payload['recipient']].flatten.compact.uniq
        @recipient      = recipient_list.collect do |email_address|
          next if email_address.to_s.empty?

          sanitize_email(email_address)
        end.compact.uniq
        @recipient_safe = recipient.collect { |r| OT::Utils.obscure_email(r) }
      end

      # Capture the selected domain the link is meant for, as long as it's
      # a valid public domain (no pub intended). This is the same validation
      # that CustomDomain objects go through so if we don't get past this
      # most basic of checks, then whatever this is never had a whisker's
      # chance in a lion's den of being a custom domain anyway.
      #
      # This records the *requested* domain only. Whether an anonymous request
      # is allowed to use it is decided later in validate_anonymous_share_domain
      # (display_domain is not reliably available this early across API versions).
      def process_share_domain
        potential_domain = sanitize_plain_text(payload['share_domain'].to_s)
        return if potential_domain.empty?

        unless Onetime::CustomDomain.valid?(potential_domain)
          secret_logger.info 'Invalid share domain',
            { domain: potential_domain, action: 'validate_share_domain', result: :invalid }
          return
        end

        # If the given domain is the same as the site's host domain, then
        # we simply skip the share domain stuff altogether.
        if Onetime::CustomDomain.default_domain?(potential_domain)
          secret_logger.info 'Ignoring default share domain',
            {
              domain: potential_domain,
              action: 'validate_share_domain',
              result: :default_domain_skipped,
            }
          return
        end

        # Otherewise, it's good to go.
        @share_domain = potential_domain
      end

      # Check each individual recipient email address using
      # the centralized Truemail-based validation. Depending
      # on the configuration, this could be a regex, mx, or
      # full smtp level check.
      def validate_recipient
        return if recipient.empty?

        if anonymous_user?
          # Account-required is an authentication failure, not a field
          # validation problem: Onetime::Unauthorized maps to 401 at the Otto
          # edge (otto_hooks.rb), where FormError's blanket handler would
          # return a misleading 422. (2026-07-29 API audit, item 2. V1 is
          # intentionally unchanged: its legacy contract collapses both
          # classes to 404, so no status bug exists there.)
          raise Onetime::Unauthorized, 'An account is required to send emails.'
        end

        recipient.each do |email_address|
          next if valid_email?(email_address)

          raise_form_error "Undeliverable email address: #{email_address}",
            field: 'recipient',
            error_type: 'invalid_email'
        end
      end

      # Validates the share domain for secret creation.
      # Determines appropriate domain and validates access permissions.
      def validate_share_domain
        validate_anonymous_share_domain
        @share_domain = determine_share_domain
        validate_domain_access(@share_domain)
      end

      # Guest share-domain policy (issue #3311): a guest's link is always created
      # on the domain they are currently visiting. The POST body can only reject
      # the request (by naming a *different* custom domain); it can never redirect
      # the link to another tenant's domain. The single exception is the operator
      # link pool (#4063), which is not a tenant domain at all — see below.
      #
      #   Guest is on…    | POST body share_domain          | Result
      #   ----------------+---------------------------------+--------------------------
      #   custom domain X | X, omitted, canonical, or junk  | allowed — link on X
      #   custom domain X | a different valid custom dom. Y | rejected (Forbidden)
      #   custom domain X | a link-pool member (#4063)      | allowed — link still on X
      #   canonical       | omitted, canonical, or junk     | allowed — link on canonical
      #   canonical       | a link-pool member (#4063)      | allowed — link on that pool
      #                   |                                 |   host, not on canonical
      #   canonical       | any other valid custom domain   | rejected (Forbidden)
      #
      # Nuance: only a valid, non-default custom domain that differs from the one
      # the guest is on counts as a smuggle. process_share_domain already filters
      # empty, malformed, and canonical/default values to nil, so they arrive here
      # as "no request" (share_domain.nil?) and are ignored rather than rejected —
      # the link is created on whatever domain the guest is on. The only legitimate
      # non-nil values are the Host-header custom domain (display_domain), i.e. a
      # guest using the /guest endpoints on a branded domain, and a link-pool host.
      #
      # Link-pool exemption (#4063) — why this does NOT reopen #3311. That rule
      # (commit 18fa96e431) protects tenant-branded CustomDomain records: brand,
      # logo, signin config, i.e. a phishing surface a guest could aim a link at.
      # A LINK_DOMAINS member is categorically not that. It is an operator-blessed
      # member of the canonical host set with NO CustomDomain record by design
      # (see link_pool_host?), an exact canonical match outranks :custom in the
      # Chooserator, and ConfigureDomains warns the operator at boot if they list
      # a host that IS registered. The exemption grants guests exactly the
      # treatment the canonical host already gets, on a host the deployment
      # serves itself.
      #
      # The guard is required, not merely tidy: this method runs BEFORE
      # validate_domain_access, so that method's pool admission is unreachable
      # for guests without it and every anonymous POST naming a pool member 403s.
      # process_share_domain only nils out ANCHOR hosts, so a non-anchor pool
      # member survives as a non-nil @share_domain — which is exactly what the
      # homepage form posts once it falls back to the pool instead of canonical
      # (the canonical-excluded case in #4063).
      #
      # DECIDED, do not "fix" this either way: a guest may name ANY pool member,
      # not just the operator's first entry. Every pool entry is operator-blessed
      # and equivalent, so free choice is the intended product behavior.
      #
      # On a branded host the exemption is inert: determine_share_domain still
      # pins guests to the Host header, so the link lands on the branded domain
      # regardless of which pool member was named.
      #
      # Authenticated callers are unaffected: domain selection is governed by
      # validate_domain_permissions (ownership / membership).
      #
      # Keep textually parallel with the V1 implementation
      # (apps/api/v1/logic/secrets/base_secret_action.rb).
      def validate_anonymous_share_domain
        return unless anonymous_user?
        return if share_domain.nil?
        return if link_pool_host?(share_domain)
        return if custom_domain? && share_domain.casecmp?(display_domain.to_s)

        secret_logger.warn 'Anonymous cross-domain share_domain rejected',
          {
            domain: share_domain,
            display_domain: display_domain,
            action: 'validate_anonymous_share_domain',
            result: :cross_domain,
          }
        raise Onetime::Forbidden.new(
          "You do not have permission to use domain: #{share_domain}",
          error_key: 'api.secrets.errors.domain_permission_anonymous_cross_domain',
          args: { domain: share_domain },
        )
      end

      # @sync src/schemas/contracts/config/public.ts — passphrase options
      def validate_passphrase
        # Get passphrase configuration
        passphrase_config = OT.conf.dig('site', 'secret_options', 'passphrase') || {}

        # Check if passphrase is required
        if passphrase_config['required'] && passphrase.to_s.empty?
          raise_form_error 'A passphrase is required for all secrets'
        end

        # Skip further validation if no passphrase provided
        return if passphrase.to_s.empty?

        # Validate minimum length
        min_length = passphrase_config['minimum_length']&.to_i
        if min_length && passphrase.length < min_length
          raise_form_error "Passphrase must be at least #{min_length} characters long"
        end

        # Validate maximum length
        max_length = passphrase_config['maximum_length'] || nil
        if max_length && passphrase.length > max_length
          raise_form_error "Passphrase must be no more than #{max_length} characters long"
        end

        # Validate complexity if required
        if passphrase_config['enforce_complexity']
          validate_passphrase_complexity
        end
      end

      def validate_passphrase_complexity
        errors = []

        # Check for at least one uppercase letter
        errors << 'uppercase letter' unless passphrase.match?(/[A-Z]/)

        # Check for at least one lowercase letter
        errors << 'lowercase letter' unless passphrase.match?(/[a-z]/)

        # Check for at least one number
        errors << 'number' unless passphrase.match?(/\d/)

        # Check for at least one symbol
        errors << 'symbol' unless passphrase.match?(%r{[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>/?~`]})

        unless errors.empty?
          raise_form_error "Passphrase must contain at least one #{errors.join(', ')}"
        end
      end

      private

      def create_secret_pair
        @receipt, @secret = Onetime::Receipt.spawn_pair(
          cust&.objid, ttl, secret_value, passphrase: passphrase, domain: share_domain, kind: kind
        )

        @greenlighted = receipt.valid? && secret.valid?
      end

      def handle_success
        return raise_form_error 'Could not store your secret' unless greenlighted

        update_stats
        send_email_to_recipient

        success_data
      end

      def update_stats
        # Track which scope fields were set for targeted persistence
        scope_fields = []

        # Index by domain first (applies to both authenticated and anonymous)
        # This enables domain owners to see activity on their branded links
        scope_fields << :domain_id if index_receipt_to_domain

        unless anonymous_user?
          cust.add_receipt receipt
          cust.increment_field :secrets_created

          # Index by organization (current context from session)
          scope_fields << :org_id if index_receipt_to_organization
        end

        # Persist only the scope fields that were set
        receipt.save_fields(*scope_fields) if scope_fields.any?

        Onetime::Customer.secrets_created.increment
      end

      # Index receipt to the current organization context
      # Enables org-scoped receipt queries via org.receipts
      # @return [Boolean] true if indexed, false otherwise
      def index_receipt_to_organization
        return false unless auth_org # auth_org comes from OrganizationContext module

        receipt.org_id = auth_org.objid
        receipt.add_to_organization_receipts(auth_org)
        # Always an authenticated creator here (guarded by auth_org and the
        # anonymous_user? check in update_stats). actor_id is the FULL objid:
        # unique traceability (AU-3 / PCI 10.2.2), resolved to an identity at
        # read time (#3637).
        receipt.record_org_secret_activity_event(
          'created',
          organization: auth_org,
          'actor' => 'creator',
          'actor_id' => cust.objid,
        )
        true
      end

      # Index receipt to the custom domain used for sharing
      # Enables domain-scoped receipt queries via custom_domain.receipts
      # @return [Boolean] true if indexed, false otherwise
      def index_receipt_to_domain
        return false unless share_domain

        domain_record = Onetime::CustomDomain.from_display_domain(share_domain)
        return false unless domain_record

        receipt.domain_id = domain_record.objid
        receipt.add_to_custom_domain_receipts(domain_record)
        true
      end

      def send_email_to_recipient
        return if recipient.nil? || recipient.empty?

        receipt.deliver_by_email cust, locale, secret, recipient.first
      end

      # Determines which domain should be used for sharing.
      #
      # share_domain is the authenticated Domain Context selection. Guest requests
      # are validated upstream by validate_anonymous_share_domain (issue #3311),
      # which rejects any anonymous attempt to use a domain other than the Host
      # header. The anonymous_user? check here is a defensive second layer: a
      # guest on a custom domain is always resolved to that Host domain regardless
      # of @share_domain. Authenticated users keep their explicit selection,
      # falling back to the Host-header domain on a custom domain with no override.
      #
      # @return [String, nil] The domain to use for sharing
      def determine_share_domain
        return display_domain if custom_domain? && anonymous_user?
        return share_domain if share_domain

        display_domain if custom_domain?
      end

      # Validates domain exists and checks access permissions.
      #
      # @param domain [String, nil] Domain to validate
      # @raise [FormError] If domain is invalid or access is not permitted
      def validate_domain_access(domain)
        return if domain.nil?

        # Operator link-pool hosts are admitted here, BEFORE the
        # CustomDomain lookup below rejects them (#4063). See
        # link_pool_host? for why they have no record to look up.
        return if link_pool_host?(domain)

        # e.g. dbkey -> customdomain:display_domain_index -> hash -> key: value
        # where key is the domain and value is the domainid
        domain_record = Onetime::CustomDomain.from_display_domain(domain)
        raise_form_error "Unknown domain: #{domain}" if domain_record.nil?

        # Resolve the anonymous-creation gate once and thread it into the
        # permission check below. Both this debug line and
        # validate_domain_permissions consult allow_public_secret_creation?, and
        # each call is an independent HomepageConfig read (one Redis HGETALL of
        # the same record) — two reads per anonymous custom-domain request
        # (#3631). Passing the resolved value down collapses that to one read
        # WITHOUT memoizing on the CustomDomain instance: an instance memo goes
        # stale after an in-request HomepageConfig write, which is why a prior
        # per-instance cache was reverted and the model predicate stays
        # read-through.
        allow_public = domain_record.allow_public_secret_creation?

        secret_logger.debug 'Validating domain access',
          {
            domain: domain,
            custom_domain: custom_domain?,
            allow_public: allow_public,
            accessible: domain_record.accessible_by?(@cust),
            user_id: @cust&.objid,
          }

        validate_domain_permissions(domain_record, allow_public)
        validate_domain_verification(domain_record)
      end

      # Whether the requested domain is a member of the operator link pool
      # (features.domains.link_domains, #4063).
      #
      # A pool member is blessed by CONFIG, not by a CustomDomain
      # registration, and having NO CustomDomain row is the expected — in
      # fact the required — state for one. That is the whole point of
      # LINK_DOMAINS: an operator offers their own link hosts without
      # creating tenant domain records for them, and no tenant can attach
      # brand or signin configuration to one. Do NOT "fix" this by
      # requiring a record or by auto-creating one; without this admission
      # every host the domain-context picker offers 422s with
      # 'Unknown domain' at secret creation.
      #
      # There is no per-domain permission to check either: pool members are
      # canonical-set members (Utils::CanonicalHosts.hosts), i.e. hosts the
      # deployment serves itself, so ownership/membership does not apply.
      # If an operator lists a host that IS a registered CustomDomain, this
      # branch wins — matching DomainStrategy, where the exact canonical
      # match outranks :custom. ConfigureDomains warns about that config.
      #
      # Normalization mirrors CustomDomain.default_domain?: display_domain
      # on the input, DomainParser on the configured hosts, so
      # 'Short.Example.COM' matches a pool entry of 'short.example.com'.
      #
      # Keep logically parallel with the V1 implementation (apps/api/v1/...);
      # logging differs because V1 has no structured secret_logger.
      #
      # @param domain [String] The requested share domain
      # @return [Boolean] true when the domain is an operator link-pool host
      def link_pool_host?(domain)
        input_display = Onetime::CustomDomain.display_domain(domain)

        Onetime::Utils::CanonicalHosts.link_pool.any? do |host|
          Onetime::Utils::DomainParser.extract_hostname(host) == input_display
        end
      rescue PublicSuffix::Error, Onetime::Problem => ex
        # Unparseable input is not a pool member. Fall through to the
        # CustomDomain lookup, which rejects it as an unknown domain.
        secret_logger.info 'Unparseable share domain for link pool check',
          { domain: domain, action: 'link_pool_host', result: :unparseable, error: ex.message }
        false
      end

      # Rejects secret creation against an unverified custom share_domain when
      # the features.domains.require_verified toggle is on. Canonical domains
      # are filtered out earlier in process_share_domain via default_domain?.
      #
      # @param domain_record [CustomDomain] The domain record to check
      # @raise [FormError] If require_verified is on and the domain is not
      #   yet verified
      def validate_domain_verification(domain_record)
        return unless OT.conf.dig('features', 'domains', 'require_verified').to_s == 'true'
        return if domain_record.verified.to_s == 'true'

        secret_logger.warn 'Unverified custom share_domain rejected',
          {
            domain: share_domain,
            user_id: @cust&.objid,
            action: 'validate_domain_verification',
            result: :unverified,
          }
        raise_form_error "Custom domain is not verified: #{share_domain}",
          field: 'share_domain',
          error_type: 'domain_unverified'
      end

      # Validates domain permissions based on context and configuration.
      #
      # @param domain_record [CustomDomain] The domain record to validate
      # @param allow_public [Boolean, nil] Pre-resolved
      #   domain_record.allow_public_secret_creation? from the caller, to avoid
      #   a second HomepageConfig read (#3631). nil means "not resolved yet" —
      #   the anonymous custom-domain branch computes it on demand, so direct
      #   callers (specs, other logic) may still pass just the record.
      # @raise [Onetime::Forbidden] If access is not permitted
      # @see docs/specs/domain-permissions/domain-permissions.md for the full truth table
      #
      # Validation Rules (issue #3073):
      # - Domain owner / org member: always permitted, regardless of toggle.
      # - Authenticated non-owner: never permitted. The Homepage Secrets toggle
      #   gates anonymous public intake; it does not let authenticated users
      #   borrow someone else's domain.
      # - Anonymous on a custom domain: gated by the Homepage Secrets toggle.
      # - Anonymous on the canonical domain (with share_domain set to a custom
      #   domain): not permitted.
      def validate_domain_permissions(domain_record, allow_public = nil)
        # Any org member can always use the domain.
        return if domain_record.accessible_by?(@cust)

        # Authenticated non-member: permission denied regardless of toggle.
        # The toggle controls anonymous traffic, not who may share via the
        # domain when authenticated.
        unless anonymous_user?
          secret_logger.warn 'Non-member attempted domain access',
            {
              domain: share_domain,
              user_id: @cust&.objid,
              action: 'validate_domain_permissions',
              result: :non_owner,
            }
          raise Onetime::Forbidden.new(
            "You do not have permission to use domain: #{share_domain}",
            error_key: 'api.secrets.errors.domain_permission_authenticated_non_owner',
            args: { domain: share_domain },
          )
        end

        # Anonymous on a custom domain: gated by the Homepage Secrets toggle
        # AND the homepage secrets_mode — a homepage presenting the incoming
        # form ('incoming' mode) is public but does not authorize anonymous
        # secret CREATION (visitors send secrets via the incoming API instead).
        if custom_domain?
          # Reuse the gate resolved by validate_domain_access when present;
          # recompute only for direct callers that pass just the record. `false`
          # is a valid pre-resolved value, so guard on nil, not falsiness.
          allow_public = domain_record.allow_public_secret_creation? if allow_public.nil?
          return if allow_public

          secret_logger.warn 'Public sharing disabled for domain',
            {
              domain: share_domain,
              user_id: @cust&.objid,
              action: 'validate_domain_permissions',
              result: :access_denied,
            }
          raise Onetime::Forbidden.new(
            "Public sharing disabled for domain: #{share_domain}",
            error_key: 'api.secrets.errors.domain_public_sharing_disabled',
            args: { domain: share_domain },
          )
        end

        # Anonymous on canonical domain attempting to share via someone else's
        # custom domain via share_domain.
        secret_logger.warn 'Anonymous cross-domain access denied',
          {
            domain: share_domain,
            action: 'validate_domain_permissions',
            result: :non_owner,
          }
        raise Onetime::Forbidden.new(
          "You do not have permission to use domain: #{share_domain}",
          error_key: 'api.secrets.errors.domain_permission_anonymous_cross_domain',
          args: { domain: share_domain },
        )
      end
    end
  end
end
