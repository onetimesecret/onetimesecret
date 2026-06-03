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
        free_ttl = Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL
        if ttl > free_ttl && auth_org && !auth_org.can?('extended_default_expiration')
          require_entitlement!('extended_default_expiration')
        end

        # Apply a global maximum
        @ttl = 30.days if ttl && ttl >= 30.days

        # Enforce bounds
        @ttl = min_ttl if ttl < min_ttl
        @ttl = max_ttl if ttl > max_ttl
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
            {
              domain: potential_domain,
              action: 'validate_share_domain',
              result: :invalid,
            }
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
          raise_form_error 'An account is required to send emails.',
            field: 'recipient',
            error_type: 'requires_account'
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

      # Guest share-domain policy (issue #3311): a guest may create links only on
      # the domain they are currently visiting.
      #
      #   Guest is on…    | POST body share_domain | Result
      #   ----------------+------------------------+------------------------------
      #   custom domain X | X (or omitted)         | allowed — link on X
      #   custom domain X | a different domain Y    | rejected (Forbidden)
      #   canonical       | any custom domain       | rejected (Forbidden)
      #   canonical       | omitted / canonical     | allowed — link on canonical
      #
      # process_share_domain captured any requested domain in @share_domain. The
      # only legitimate anonymous value is the custom domain named by the Host
      # header (display_domain) — i.e. a guest using the /guest endpoints on a
      # branded domain. Everything else is a cross-domain smuggle and is rejected
      # here, before determine_share_domain resolves the domain and
      # validate_domain_access uses it.
      #
      # Authenticated callers are unaffected: domain selection is governed by
      # validate_domain_permissions (ownership / membership).
      def validate_anonymous_share_domain
        return unless anonymous_user?
        return if share_domain.nil?
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

        # e.g. dbkey -> customdomain:display_domain_index -> hash -> key: value
        # where key is the domain and value is the domainid
        domain_record = Onetime::CustomDomain.from_display_domain(domain)
        raise_form_error "Unknown domain: #{domain}" if domain_record.nil?

        secret_logger.debug 'Validating domain access',
          {
            domain: domain,
            custom_domain: custom_domain?,
            allow_public: domain_record.allow_public_homepage?,
            is_owner: domain_record.owner?(@cust),
            user_id: @cust&.objid,
          }

        validate_domain_permissions(domain_record)
        validate_domain_verification(domain_record)
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
      # @raise [Onetime::Forbidden] If access is not permitted
      # @see docs/specs/domain-permissions.md for the full truth table
      #
      # Validation Rules (issue #3073):
      # - Domain owner / org member: always permitted, regardless of toggle.
      # - Authenticated non-owner: never permitted. The Homepage Secrets toggle
      #   gates anonymous public intake; it does not let authenticated users
      #   borrow someone else's domain.
      # - Anonymous on a custom domain: gated by the Homepage Secrets toggle.
      # - Anonymous on the canonical domain (with share_domain set to a custom
      #   domain): not permitted.
      def validate_domain_permissions(domain_record)
        # Owner / org member can always use the domain.
        return if domain_record.owner?(@cust)

        # Authenticated non-owner: permission denied regardless of toggle.
        # The toggle controls anonymous traffic, not who may share via the
        # domain when authenticated.
        unless anonymous_user?
          secret_logger.warn 'Non-owner attempted domain access',
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

        # Anonymous on a custom domain: gated by the Homepage Secrets toggle.
        if custom_domain?
          return if domain_record.allow_public_homepage?

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
