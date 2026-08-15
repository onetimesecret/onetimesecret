# apps/api/v1/logic/secrets/base_secret_action.rb
#
# frozen_string_literal: true

module V1::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # V1 Secret Creation Logic [#2615]
    #
    # TTL bounds come from site.secret_options in config. The config path
    # is OT.conf.dig('site', 'secret_options') — NOT a top-level fetch.
    # If the config key is missing, the hardcoded fallback applies:
    #   ttl_options: [30.minutes, 2.hours, 1.day, 7.days]
    #   default_ttl: 7.days
    #
    # In practice, the fallback rarely triggers because OT::Config.after_load
    # deep-merges DEFAULTS into the loaded config. When the YAML sets a key
    # to nil (e.g. `ttl_options: <%= nil %>`), deep_merge preserves the
    # DEFAULTS value — so the effective max comes from Config::DEFAULTS
    # (currently 30.days / 2,592,000s). See Config.deep_merge nil semantics.
    #
    # v0.23.x vs v0.24 behavioral differences (not bugs):
    #   TTL max:         v0.23 used plan.options[:ttl] (14 days for most plans)
    #                    v0.24 resolves org from customer for plan-aware limits:
    #                    14 days free tier, 30 days paid/billing-disabled.
    #   Passphrase min:  v0.23 hardcoded 8 chars; v0.24 is config-driven
    #                    (site.secret_options.passphrase.minimum_length)
    #   Secret keys:     v0.23 generated 31-char keys; v0.24 generates 64-char
    #                    keys (intentional — more secure algorithm), with
    #                    shortkey truncation at 8 chars (was 6)
    #
    # The metadata_ttl = 2 * secret_ttl ratio is unchanged from v0.23.x.
    #
    class BaseSecretAction < V1::Logic::Base
      # V1-specific validation boundaries [#2621]
      #
      # These constants preserve v0.23.4 behavior for backward compatibility.
      # V1 consumers rely on these bounds; changing them is a breaking change.
      #
      # TTL: v0.23.4 allowed 60s minimum; v0.24 raised it to 1800s.
      # V1 preserves the old 60s floor so existing integrations don't break.
      V1_MIN_TTL = 60        # 1 minute, matching v0.23.4
      V1_MAX_TTL = 2_592_000 # 30 days (30 * 86400)

      # Passphrase minimum length: config-driven with nil fallback [#2758]
      #
      # When the operator sets `site.secret_options.passphrase.minimum_length`
      # in config, V1 now respects that value. When unset (nil), no minimum
      # is enforced — preserving backward compatibility for callers sending
      # short passphrases (e.g. "1234").
      #
      # This changed in v0.24.1: prior versions hard-coded nil here, ignoring
      # any operator config. Now operators can opt-in to enforcement.
      def self.passphrase_min_length
        OT.conf.dig('site', 'secret_options', 'passphrase', 'minimum_length')&.to_i
      end

      # Max secret size: 10_000 matches the API spec's maxLength: 10000
      # documented in the OpenAPI definition. Enforced in BYTES (C5): a
      # character-denominated check admits up to 4x the cap in Redis for
      # multibyte content, so the byte measure is what actually bounds storage.
      V1_MAX_SECRET_SIZE = 10_000

      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :greenlighted, :receipt, :secret, :share_domain, :custom_domain, :payload, :default_expiration

      # Process methods populate instance variables with the values. The
      # raise_concerns and process methods deal with the values in the instance
      # variables only (no more params access).
      def process_params
        # V1 uses flat query/form params: params['secret'], params['ttl'], etc.
        # (V2/V3 use a nested 'secret' namespace; V1 does not.)
        @payload = params || {}
        raise_form_error 'Incorrect payload format' if payload.is_a?(String)
        process_ttl
        process_secret
        process_passphrase
        process_recipient
        process_share_domain
      end

      def raise_concerns
        raise_form_error 'Unknown type of secret' if kind.nil?
        validate_secret_size
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
            metadata: receipt.safe_dump, # maintain public API
            secret: secret.safe_dump,
            share_domain: share_domain,
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
        ['/receipt/', receipt.key].join
      end

      protected

      def process_ttl
        @ttl = payload.fetch('ttl', nil)

        # Config resolution chain:
        #   1. OT::Config.after_load deep-merges DEFAULTS into loaded YAML
        #   2. YAML nil values are preserved as DEFAULTS (deep_merge skips nil)
        #   3. This dig reads the merged result — DEFAULTS wins when YAML is nil
        #
        # The inline fallback hash below only triggers if the entire
        # site.secret_options key is absent (should not happen after after_load).
        #
        # V1-specific TTL bounds [#2621]:
        #   min = V1_MIN_TTL (60s), max = V1_MAX_TTL (30 days)
        # These preserve v0.23.4 behavior. The config values are used for
        # default_ttl only; bounds are V1-specific constants.
        secret_options = OT.conf.dig('site', 'secret_options') || {
          'default_ttl' => 7.days,
          'ttl_options' => [30.minutes, 2.hours, 1.day, 7.days],
        }
        default_ttl    = secret_options['default_ttl']

        # V1 uses its own TTL bounds, not the config's ttl_options min/max.
        # This preserves v0.23.4 behavior where 60s was the minimum.
        min_ttl = V1_MIN_TTL
        max_ttl = V1_MAX_TTL

        # TTL ceiling dispatch — mirrors V2's three-way structure (#4172).
        #
        # 1. auth_org present (V1 specs that inject one): plan limit
        # 2. anonymous caller: configured anonymous ceiling (default 7 days)
        # 3. authenticated without OrganizationContext: resolve via billing/org lookup
        #
        # Before #4172 the anonymous case fell through to resolve_ttl_limit,
        # which returned the bare V1_MAX_TTL (30 days) when billing was
        # disabled — 4× wider than the configured anonymous ceiling.
        caller_max = if respond_to?(:auth_org) && auth_org.respond_to?(:limit_for)
                       org_limit = auth_org.limit_for('secret_lifetime')
                       org_limit.positive? ? org_limit : max_ttl
                     elsif cust.nil? || cust.anonymous?
                       anonymous_max_ttl(max_ttl)
                     else
                       resolve_ttl_limit(max_ttl)
                     end

        # Apply default if nil
        @ttl = default_ttl || 7.days if ttl.nil?

        # Convert to integer, now that we know it has a value
        @ttl = ttl.to_i

        # V1 TTL clamping [#2621]: silently clamp to V1 bounds.
        # v0.23.4 silently clamped rather than rejecting, so V1 preserves
        # that behavior for backward compatibility. Clamping happens BEFORE
        # the entitlement gate so that e.g. ttl=9999999 gets clamped to
        # 30 days rather than rejected for missing entitlements.
        # caller_max may be lower than max_ttl, so use the stricter ceiling.
        effective_max_ttl = [max_ttl, caller_max].min
        @ttl              = ttl.clamp(min_ttl, effective_max_ttl)

        # Entitlement gate: requests beyond free tier TTL require extended_default_expiration.
        # Checked after clamping so the effective (clamped) value is evaluated.
        # V1::Logic::Base has no require_entitlement! (no strategy_result, so no
        # membership context for the ADR-012 membership check), so raise directly
        # with the same upgrade-path shape the shared helper produces.
        free_ttl = Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL
        if ttl > free_ttl && respond_to?(:auth_org) && auth_org && !auth_org.can?('extended_default_expiration')
          current_plan = auth_org.planid
          upgrade_to   = if defined?(Billing::PlanHelpers)
                           Billing::PlanHelpers.upgrade_path_for('extended_default_expiration', current_plan)
                         end
          raise Onetime::EntitlementRequired.new(
            'extended_default_expiration',
            current_plan: current_plan,
            upgrade_to: upgrade_to,
            error_key: 'api.entitlements.errors.extended_default_expiration_required',
            args: { entitlement: 'extended_default_expiration' },
          )
        end

        # Set default_expiration for compatibility with tests
        @default_expiration = @ttl
      end

      def process_secret
        raise NotImplementedError, 'You must implement process_secret'
      end

      def process_passphrase
        @passphrase = payload['passphrase'].to_s
      end

      # Sanitizes but does not validate as an email address.
      def process_recipient
        payload['recipient'] = [payload['recipient']].flatten.compact.uniq # force a list
        @recipient           = payload['recipient'].collect do |email_address|
          next if email_address.to_s.empty?

          sanitize_email(email_address)
        end.compact.uniq
        @recipient_safe      = recipient.collect { |r| OT::Utils.obscure_email(r) }
      end

      # Capture the selected domain the link is meant for, as long as it's
      # a valid public domain (no pub intended). This is the same validation
      # that CustomDomain objects go through so if we don't get past this
      # most basic of checks, then whatever this is never had a whisker's
      # chance in a lion's den of being a custom domain anyway.
      #
      # This records the *requested* domain only. Whether an anonymous request
      # is allowed to use it is decided later in validate_anonymous_share_domain
      # (display_domain is not set on V1 logic objects until the controller
      # applies domain context, after construction).
      def process_share_domain
        potential_domain = sanitize_plain_text(payload['share_domain'].to_s)
        return if potential_domain.empty?

        unless Onetime::CustomDomain.valid?(potential_domain)
          return OT.info "[BaseSecretAction] Invalid share domain #{potential_domain}"
        end

        # If the given domain is the same as the site's host domain, then
        # we simply skip the share domain stuff altogether.
        if Onetime::CustomDomain.default_domain?(potential_domain)
          return OT.info "[BaseSecretAction] Ignoring default share domain: #{potential_domain}"
        end

        # Otherewise, it's good to go.
        @share_domain = potential_domain
      end

      # V1 secret size enforcement [#2621]
      #
      # The API spec documents maxLength: 10000 but this was never enforced
      # in code. V1 now enforces the documented limit to prevent abuse and
      # ensure consistent behavior with the API documentation. Byte-measured
      # to match the shared V2 path (C5).
      def validate_secret_size
        return if secret_value.nil?
        return if secret_value.to_s.bytesize <= V1_MAX_SECRET_SIZE

        raise_form_error "Secret value exceeds the maximum size of #{V1_MAX_SECRET_SIZE} bytes"
      end

      def validate_recipient
        return if recipient.empty?

        raise_form_error 'An account is required to send emails.' if cust.nil? || cust.anonymous?
        recipient.each do |recip|
          # Use Truemail validation (same as rest of application) rather
          # than regex-only v1_valid_email?. This is a security improvement
          # over v0.23.4 behavior — email delivery should be validated.
          raise_form_error "Undeliverable email address: #{recip}" unless valid_email?(recip)
        end
      end

      # Validates the share domain for secret creation.
      # Determines appropriate domain and validates access permissions.
      def validate_share_domain
        validate_anonymous_share_domain
        # If we're on a custom domain creating a link, the only possible share
        # domain  is the custom domain itself. This is bc we only allow logging
        # in on the canonical domain (e.g. onetimesecret.com) AND we don't offer
        # any way to change the share domain when creating a link from a custom
        # domain.
        @share_domain = determine_share_domain
        validate_domain_access(@share_domain)
      end

      # Guests may create links only on the domain they are currently visiting,
      # or on an operator link-pool host (#4063).
      #
      # process_share_domain captured any requested domain in @share_domain. For
      # an anonymous request the legitimate values are the custom domain named by
      # the Host header (display_domain) — a guest creating links for that same
      # branded domain — and a link-pool member. Any other custom domain is a
      # cross-domain smuggle: a guest on the canonical domain naming a custom
      # domain, or a guest on one custom domain naming a different one (issue
      # #3311). Those are rejected here, before determine_share_domain pins the
      # resolved domain to the Host header.
      #
      #   Guest is on…    | POST body share_domain          | Result
      #   ----------------+---------------------------------+--------------------------
      #   custom domain X | X, omitted, canonical, or junk  | allowed — link on X
      #   custom domain X | a different valid custom dom. Y | rejected (FormError)
      #   custom domain X | a link-pool member (#4063)      | allowed — link still on X
      #   canonical       | omitted, canonical, or junk     | allowed — link on canonical
      #   canonical       | a link-pool member (#4063)      | allowed — link on that pool
      #                   |                                 |   host, not on canonical
      #   canonical       | any other valid custom domain   | rejected (FormError)
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
      # for guests without it and every anonymous POST naming a pool member is
      # rejected. process_share_domain only nils out ANCHOR hosts, so a
      # non-anchor pool member survives as a non-nil @share_domain — which is
      # exactly what the homepage form posts once it falls back to the pool
      # instead of canonical (the canonical-excluded case in #4063).
      #
      # DECIDED, do not "fix" this either way: a guest may name ANY pool member,
      # not just the operator's first entry. Every pool entry is operator-blessed
      # and equivalent, so free choice is the intended product behavior.
      #
      # On a branded host the exemption is inert: determine_share_domain returns
      # display_domain whenever custom_domain?, so the link lands on the branded
      # domain regardless of which pool member was named.
      #
      # Keep textually parallel with the V2 implementation
      # (apps/api/v2/logic/secrets/base_secret_action.rb).
      def validate_anonymous_share_domain
        return unless cust.nil? || cust.anonymous?
        return if share_domain.nil?
        return if link_pool_host?(share_domain)
        return if custom_domain? && share_domain.casecmp?(display_domain.to_s)

        OT.li "[validate_anonymous_share_domain]: #{share_domain} cross-domain from #{display_domain} [#{cust&.custid}]"
        raise_form_error "You do not have permission to use domain: #{share_domain}"
      end

      # @sync src/schemas/contracts/config/public.ts — passphrase options
      def validate_passphrase
        # V1 passphrase validation [#2758]
        #
        # When the operator sets minimum_length in config, V1 now enforces it.
        # When unset (nil), no minimum is enforced — preserving backward
        # compatibility for callers sending short passphrases.
        passphrase_config = OT.conf.dig('site', 'secret_options', 'passphrase') || {}

        # Check if passphrase is required (defaults to false for V1 compat)
        if passphrase_config['required'] && passphrase.to_s.empty?
          raise_form_error 'A passphrase is required for all secrets'
        end

        # Skip further validation if no passphrase provided
        return if passphrase.to_s.empty?

        # Config-driven minimum length; nil means no enforcement
        min_length = self.class.passphrase_min_length
        if min_length && passphrase.length < min_length
          raise_form_error "Passphrase must be at least #{min_length} characters long"
        end

        # Validate maximum length (shared with all versions)
        max_length = passphrase_config['maximum_length']
        if max_length && passphrase.length > max_length
          raise_form_error "Passphrase must be no more than #{max_length} characters long"
        end

        # V1 does not enforce complexity — preserves v0.23.4 behavior.
        # The enforce_complexity config option is ignored for V1 API.
      end

      private

      # Resolve max TTL for an authenticated caller without OrganizationContext.
      #
      # Only reached for authenticated users — anonymous callers are dispatched
      # to anonymous_max_ttl by the three-way split in process_ttl (#4172).
      #
      # Looks up the customer's organization to check plan-based limits.
      # Billing-disabled (self-hosted) deployments get config_max (30 days).
      #
      # Codeflow for organization_instances (Familia participates_in):
      #   1. Customer.participates_in :Organization, :members (customer.rb:116)
      #      generates cust.organization_instances, organization_ids, organization?, etc.
      #   2. organization_instances calls participating_ids_for_target(Organization)
      #      which scans the customer's `participations` Redis set (all relationship
      #      types: orgs, domains, etc.), filtering by the "organization" key prefix.
      #   3. Matching IDs are passed to Organization.load_multi(ids) — one HGETALL
      #      per org — and the result is already an Array (compact'd).
      #   4. .to_a is therefore a no-op (load_multi returns Array). Kept for
      #      defensive clarity but has zero cost.
      #   5. .first picks the first org. Typical customer has exactly 1 org
      #      (created on signup), so the scan + load is ~1 set read + 1 HGETALL.
      #
      # Lighter alternative if needed: Organization.load(cust.organization_ids.first)
      # skips loading all org objects. Not worth the change at current scale.
      #
      # @param config_max [Integer] Fallback from config ttl_options.max
      # @return [Integer] Maximum TTL in seconds
      def resolve_ttl_limit(config_max)
        billing_enabled = begin
          Onetime::BillingConfig.instance.enabled?
        rescue StandardError
          false
        end

        # Billing disabled (self-hosted): fail-open at config max
        return config_max unless billing_enabled

        # Authenticated: look up customer's org for plan-based limit
        resolved_org = cust.organization_instances.to_a.first
        if resolved_org.respond_to?(:limit_for)
          org_limit = resolved_org.limit_for('secret_lifetime')
          return org_limit.positive? ? [org_limit, config_max].min : config_max
        end

        # No org found (edge case): fall back to free tier limit
        free_max = Onetime::Organization.free_tier_limits['secret_lifetime.max']
        free_max.positive? ? free_max : config_max
      rescue StandardError => ex
        OT.ld "[BaseSecretAction] TTL limit resolution failed: #{ex.message}"
        config_max
      end

      # Anonymous TTL ceiling (#4172), mirroring V2's anonymous_max_ttl.
      #
      # Lowest of up to three ceilings:
      #   1. configured_anonymous_max_ttl (default 7 days, env TTL_MAX_ANONYMOUS)
      #   2. config_max (V1_MAX_TTL, so a global cap still wins)
      #   3. free-tier secret_lifetime limit (only when billing is enabled)
      #
      # @param config_max [Integer] V1_MAX_TTL fallback
      # @return [Integer] Maximum TTL in seconds for anonymous callers
      def anonymous_max_ttl(config_max)
        ceilings = [
          Onetime::Models::Features::WithEntitlements.configured_anonymous_max_ttl,
          config_max,
        ]

        billing_enabled = begin
          Onetime::BillingConfig.instance.enabled?
        rescue StandardError => ex
          OT.ld "[anonymous_max_ttl] BillingConfig unavailable (#{ex.class}: #{ex.message}); " \
                "anonymous TTL ceiling falls back to #{ceilings.min}"
          false
        end

        if billing_enabled
          free_tier_max = Onetime::Organization.free_tier_limits['secret_lifetime.max'].to_i
          ceilings << free_tier_max if free_tier_max.positive?
        end

        ceilings.min
      end

      # Creates the receipt/secret pair using the modern Metadata.spawn_pair API.
      #
      # IMPORTANT: Uses cust.objid (non-PII identifier) NOT cust.custid (email).
      # The legacy custid field stored email addresses; owner_id stores objid.
      # See: Onetime::Receipt.spawn_pair in lib/onetime/models/receipt.rb
      #
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
      end

      def update_stats
        unless cust.nil? || cust.anonymous?
          cust.add_receipt receipt
          cust.increment_field :secrets_created # cust.secrets_created.increment
        end
        # TODO:
        # Onetime::Customer.global.increment_field :secrets_created # Customer.secrets_created.increment
      end

      def send_email_to_recipient
        return if recipient.nil? || recipient.empty?

        receipt.deliver_by_email cust, locale, secret, recipient.first
      end

      # Determines which domain should be used for sharing.
      # Uses display domain if on custom domain, otherwise uses specified share domain.
      #
      # @return [String, nil] The domain to use for sharing
      def determine_share_domain
        return display_domain if custom_domain?

        share_domain
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

        # Resolve the anonymous-creation gate once and pass it to
        # validate_domain_permissions so the debug line and the permission check
        # share a single HomepageConfig read instead of two (#3631). Not memoized
        # on the domain instance: an instance cache goes stale after an in-request
        # HomepageConfig write, which is why the model predicate stays read-through.
        allow_public = domain_record.allow_public_secret_creation?

        OT.ld <<~DEBUG
          [BaseSecretAction]
            class:     #{self.class}
            share_domain:   #{@share_domain}
            custom_domain?:  #{custom_domain?}
            allow_public?:   #{allow_public}
            accessible?:     #{domain_record.accessible_by?(@cust)}
            verified?:       #{domain_record.verified}
        DEBUG

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
      # Membership is answered by Middleware::DomainStrategy.link_pool_host?,
      # NOT by reading features.domains.link_domains out of config. The config
      # read skipped both of the middleware's gates — features.domains.enabled,
      # and membership in the parsed canonical set — so with domains disabled,
      # or with an entry that does not parse, this admitted hosts the
      # middleware classifies :invalid and the picker never offers. Admission
      # here and classification there must answer from the same set.
      #
      # Normalization mirrors CustomDomain.default_domain?: display_domain on
      # the input (which also rejects garbage, via the rescue below),
      # DomainParser on the resolved pool, so 'Short.Example.COM' matches a
      # pool entry of 'short.example.com'.
      #
      # Keep logically parallel with the V2 implementation
      # (apps/api/v2/logic/secrets/base_secret_action.rb); logging differs
      # because V2 uses the structured secret_logger.
      #
      # @param domain [String] The requested share domain
      # @return [Boolean] true when the domain is an operator link-pool host
      def link_pool_host?(domain)
        input_display = Onetime::CustomDomain.display_domain(domain)

        Onetime::Middleware::DomainStrategy.link_pool_host?(input_display)
      rescue PublicSuffix::Error, Onetime::Problem => ex
        # Unparseable input is not a pool member. Fall through to the
        # CustomDomain lookup, which rejects it as an unknown domain.
        OT.le "[link_pool_host?] #{ex.message} for `#{domain}`"
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

        OT.li "[validate_domain_verif]: #{share_domain} unverified [#{cust&.custid}]"
        raise_form_error "Custom domain is not verified: #{share_domain}"
      end

      # Validates domain permissions based on context and configuration.
      #
      # @param domain_record [CustomDomain] The domain record to validate
      # @param allow_public [Boolean, nil] Pre-resolved
      #   domain_record.allow_public_secret_creation? from the caller, to avoid
      #   a second HomepageConfig read (#3631). nil means "not resolved yet" —
      #   the anonymous custom-domain branch computes it on demand, so direct
      #   callers may still pass just the record.
      # @raise [FormError] If access is not permitted
      # @see docs/specs/domain-permissions/domain-permissions.md for the full truth table
      #
      # Validation Rules (issue #3073):
      # - Domain owner / org member: always permitted, regardless of toggle.
      # - Authenticated non-owner: never permitted. The Homepage Secrets toggle
      #   gates anonymous public intake only.
      # - Anonymous on a custom domain: gated by the Homepage Secrets toggle.
      # - Anonymous on canonical with share_domain set: not permitted.
      def validate_domain_permissions(domain_record, allow_public = nil)
        # Any org member can always use the domain.
        return if domain_record.accessible_by?(@cust)

        # Authenticated non-member: permission denied regardless of toggle.
        unless cust.nil? || cust.anonymous?
          OT.li "[validate_domain_perm]: #{share_domain} non-member [#{cust.custid}]"
          raise_form_error "You do not have permission to use domain: #{share_domain}"
        end

        # Anonymous on a custom domain: gated by the Homepage Secrets toggle
        # AND the homepage secrets_mode — 'incoming' mode does not authorize
        # anonymous secret creation (visitors use the incoming API instead).
        if custom_domain?
          # Reuse the caller-resolved gate when present; recompute only for
          # direct callers that pass just the record. Guard on nil since false
          # is a valid pre-resolved value.
          allow_public = domain_record.allow_public_secret_creation? if allow_public.nil?
          return if allow_public

          raise_form_error "Public sharing disabled for domain: #{share_domain}"
        end

        # Anonymous on canonical domain attempting to use someone else's domain.
        raise_form_error "You do not have permission to use domain: #{share_domain}"
      end
    end
  end
end
