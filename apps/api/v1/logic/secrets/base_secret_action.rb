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

      # Passphrase: v0.23.4 had no enforced minimum for V1 API consumers.
      # The config-driven minimum (often 8) is for the web UI. V1 API
      # preserves nil (no minimum) unless the operator explicitly sets one.
      V1_PASSPHRASE_MIN_LENGTH = nil

      # Max secret size: 10_000 characters matches the API spec's
      # maxLength: 10000 documented in the OpenAPI definition.
      V1_MAX_SECRET_SIZE = 10_000

      # Email validation regex - defined once to avoid recompilation on every call.
      # TLD allows 2+ chars to support modern TLDs (.technology, .international)
      # that would be silently dropped by the old {2,4} limit before reaching
      # v1_valid_email? (RFC 5321) validation.
      EMAIL_REGEX = /\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b/

      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :greenlighted
      attr_reader :receipt, :secret, :share_domain, :custom_domain, :payload, :default_expiration

      # Process methods populate instance variables with the values. The
      # raise_concerns and process methods deal with the values in the instance
      # variables only (no more params access).
      def process_params
        # V1 uses flat query/form params: params['secret'], params['ttl'], etc.
        # (V2/V3 use a nested 'secret' namespace; V1 does not.)
        @payload = params || {}
        raise_form_error "Incorrect payload format" if payload.is_a?(String)
        process_ttl
        process_secret
        process_passphrase
        process_recipient
        process_share_domain
      end

      def raise_concerns
        raise_form_error "Unknown type of secret" if kind.nil?
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
        default_ttl = secret_options['default_ttl']

        # V1 uses its own TTL bounds, not the config's ttl_options min/max.
        # This preserves v0.23.4 behavior where 60s was the minimum.
        min_ttl = V1_MIN_TTL
        max_ttl = V1_MAX_TTL

        # Plan-aware TTL cap: resolve the customer's org for plan limits.
        # Falls back to V1_MAX_TTL when billing is disabled (self-hosted).
        plan_max = if respond_to?(:org) && org&.respond_to?(:limit_for)
                     org_limit = org.limit_for('secret_lifetime')
                     org_limit.positive? ? org_limit : max_ttl
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
        @ttl = max_ttl if ttl > max_ttl
        @ttl = min_ttl if ttl < min_ttl

        # Further constrain by plan limit (may be lower than V1_MAX_TTL)
        @ttl = plan_max if ttl > plan_max

        # Entitlement gate: requests beyond free tier TTL require extended_default_expiration.
        # Checked after clamping so the effective (clamped) value is evaluated.
        free_ttl = Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL
        if ttl > free_ttl && respond_to?(:org) && org && !org.can?('extended_default_expiration')
          require_entitlement!('extended_default_expiration')
        end

        # Set default_expiration for compatibility with tests
        @default_expiration = @ttl
      end

      def process_secret
        raise NotImplementedError, "You must implement process_secret"
      end

      def process_passphrase
        @passphrase = payload['passphrase'].to_s
      end

      def process_recipient
        payload['recipient'] = [payload['recipient']].flatten.compact.uniq # force a list
        @recipient = payload['recipient'].collect { |email_address|
          next if email_address.to_s.empty?
          sanitized_email = sanitize_email(email_address)
          sanitized_email.scan(EMAIL_REGEX).uniq.first
        }.compact.uniq
        @recipient_safe = recipient.collect { |r| OT::Utils.obscure_email(r) }
      end

      # Capture the selected domain the link is meant for, as long as it's
      # a valid public domain (no pub intended). This is the same validation
      # that CustomDomain objects go through so if we don't get past this
      # most basic of checks, then whatever this is never had a whisker's
      # chance in a lion's den of being a custom domain anyway.
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
      # ensure consistent behavior with the API documentation.
      def validate_secret_size
        return if secret_value.nil?
        return if secret_value.length <= V1_MAX_SECRET_SIZE

        raise_form_error "Secret value exceeds the maximum size of #{V1_MAX_SECRET_SIZE} characters"
      end

      def validate_recipient
        return if recipient.empty?
        raise_form_error "An account is required to send emails." if cust.anonymous?
        recipient.each do |recip|
          raise_form_error "Undeliverable email address: #{recip}" unless v1_valid_email?(recip)
        end
      end

      # Validates the share domain for secret creation.
      # Determines appropriate domain and validates access permissions.
      def validate_share_domain
        # If we're on a custom domain creating a link, the only possible share
        # domain  is the custom domain itself. This is bc we only allow logging
        # in on the canonical domain (e.g. onetimesecret.com) AND we don't offer
        # any way to change the share domain when creating a link from a custom
        # domain.
        @share_domain = determine_share_domain
        validate_domain_access(@share_domain)
      end

      def validate_passphrase
        # V1-specific passphrase validation [#2621]
        #
        # V1 preserves v0.23.4 behavior: passphrases are always optional
        # and have no minimum length enforced via the API. The config-driven
        # minimum_length (often 8) is for the web UI; V1 API consumers
        # relied on being able to send short passphrases (e.g. "1234").
        #
        # Only the maximum length and required flag are checked from config.
        passphrase_config = OT.conf.dig('site', 'secret_options', 'passphrase') || {}

        # Check if passphrase is required (defaults to false for V1 compat)
        if passphrase_config['required'] && passphrase.to_s.empty?
          raise_form_error "A passphrase is required for all secrets"
        end

        # Skip further validation if no passphrase provided
        return if passphrase.to_s.empty?

        # V1 uses its own minimum length (nil = no minimum) instead of
        # the config value, preserving v0.23.4 backward compatibility.
        min_length = V1_PASSPHRASE_MIN_LENGTH
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

      # Resolve max TTL when OrganizationContext is not available (V1).
      #
      # Looks up the customer's organization to check plan-based limits.
      # Billing-disabled (self-hosted) deployments get config_max (30 days).
      # Billing-enabled free/anonymous users get the free tier limit (14 days).
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

        # Anonymous users: free tier limit
        if cust.nil? || cust.anonymous?
          free_max = Onetime::Models::Features::WithEntitlements
                       .free_tier_limits['secret_lifetime.max']
          return free_max.positive? ? free_max : config_max
        end

        # Authenticated: look up customer's org for plan-based limit
        resolved_org = cust.organization_instances.to_a.first
        if resolved_org&.respond_to?(:limit_for)
          org_limit = resolved_org.limit_for('secret_lifetime')
          return org_limit.positive? ? [org_limit, config_max].min : config_max
        end

        # No org found (edge case): fall back to free tier limit
        free_max = Onetime::Models::Features::WithEntitlements
                     .free_tier_limits['secret_lifetime.max']
        free_max.positive? ? free_max : config_max
      rescue StandardError => e
        OT.ld "[BaseSecretAction] TTL limit resolution failed: #{e.message}"
        config_max
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
        return raise_form_error "Could not store your secret" unless greenlighted
        update_stats
        send_email_to_recipient
      end

      def update_stats
        unless cust.anonymous?
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

        # e.g. dbkey -> customdomain:display_domains -> hash -> key: value
        # where key is the domain and value is the domainid
        domain_record = Onetime::CustomDomain.from_display_domain(domain)
        raise_form_error "Unknown domain: #{domain}" if domain_record.nil?

        OT.ld <<~DEBUG
          [BaseSecretAction]
            class:     #{self.class}
            share_domain:   #{@share_domain}
            custom_domain?:  #{custom_domain?}
            allow_public?:   #{domain_record.allow_public_homepage?}
            owner?:          #{domain_record.owner?(@cust)}
        DEBUG

        validate_domain_permissions(domain_record)
      end

      # Validates domain permissions based on context and configuration.
      #
      # @param domain_record [CustomDomain] The domain record to validate
      # @raise [FormError] If access is not permitted
      #
      # Validation Rules:
      # - On custom domains:
      #   - Allows access if public sharing is enabled
      #   - Rejects if public sharing is disabled
      # - On canonical domain:
      #   - Requires domain ownership
      def validate_domain_permissions(domain_record)
        if custom_domain?
          return if domain_record.allow_public_homepage?
          raise_form_error "Public sharing disabled for domain: #{share_domain}"
        end

        unless domain_record.owner?(@cust)
          OT.li "[validate_domain_perm]: #{share_domain} non-owner [#{cust.custid}]"
        end
      end
    end
  end
end
