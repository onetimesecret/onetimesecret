# apps/api/v2/logic/secrets/burn_secret.rb
#
# frozen_string_literal: true

require 'onetime/security/passphrase_rate_limiter'

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # Burn Secret
    #
    # @api Permanently destroys a secret before its expiration time. Requires
    #   the receipt identifier and a passphrase if one was set. Returns the
    #   updated receipt record with burn confirmation and related URLs.
    #
    # SECURITY NOTE: Ownership Not Required
    # =====================================
    # This endpoint intentionally does NOT check ownership. Any user (or anonymous
    # visitor) with the receipt identifier can burn a secret. This is by-design for
    # the one-time secret sharing model:
    #
    # - The receipt URL is the credential for accessing/burning the secret
    # - Secrets are meant to be burned by the recipient, not the creator
    # - Passphrase protection provides an additional layer if needed
    # - The secret creator shares the receipt URL and trusts the recipient
    #
    # If ownership-restricted burning is desired, use the owner-facing burn
    # endpoint on the receipt page (which requires session authentication).
    class BurnSecret < V2::Logic::Base
      include Onetime::LoggerMethods
      include Onetime::Logic::GuestRouteGating
      include Onetime::Security::PassphraseRateLimiter
      include ActorAttribution

      SCHEMAS = { response: 'receipt' }.freeze

      attr_reader :identifier, :passphrase, :continue, :receipt, :secret, :correct_passphrase, :greenlighted

      def process_params
        @identifier = sanitize_identifier(params['identifier'])
        @receipt    = Onetime::Receipt.load identifier
        @passphrase = params['passphrase'].to_s
        @continue   = [true, 'true'].include?(params['continue'])
      end

      def raise_concerns
        require_guest_route_enabled!(:burn)
        require_entitlement!('api_access')
        raise OT::MissingSecret if receipt.nil?
      end

      def process
        potential_secret = @receipt.load_secret

        return unless potential_secret

        # Check passphrase rate limit before allowing passphrase attempts.
        # Burn is the same brute-force oracle as show/reveal: each wrong
        # guess confirms the passphrase is wrong, and a correct guess
        # destroys the secret.
        check_passphrase_rate_limit!(potential_secret.identifier, passphrase_client_ip) if potential_secret.has_passphrase?

        @correct_passphrase = !potential_secret.has_passphrase? || potential_secret.passphrase?(passphrase)
        viewable            = potential_secret.viewable?
        # Use the parsed boolean (true / 'true' only), not the raw param: the
        # raw value treats any non-empty string as truthy, so a deliberate
        # `continue=false` would burn the secret anyway.
        @greenlighted       = viewable && correct_passphrase && continue

        secret_logger.debug 'Secret burn initiated',
          {
            receipt_identifier: receipt.identifier,
            secret_identifier: potential_secret.shortid,
            viewable: viewable,
            has_passphrase: potential_secret.has_passphrase?,
            passphrase_correct: correct_passphrase,
            continue: continue,
            user_id: cust&.custid,
          }

        if greenlighted
          @secret = potential_secret

          # Clear any rate limit state on successful passphrase entry
          clear_passphrase_rate_limit!(secret.identifier, passphrase_client_ip) if secret.has_passphrase?

          # Attribute the burn BEFORE burned! consumes the secret: owner?(cust)
          # reads the still-in-memory owner_id, so the 'burned' audit event
          # records who acted (#3639). Anonymous guard in lifecycle_actor_context.
          actor_context = lifecycle_actor_context(secret)

          # Gate all bookkeeping on winning the atomic burn claim: burned!
          # returns true only for the single caller that flips the state. When
          # a concurrent reveal or burn already consumed the secret, this
          # request lost the race -- it must not count the burn, log success,
          # or report success to the client.
          @greenlighted = secret.burned!(actor_context: actor_context)

          if greenlighted
            owner = secret.load_owner
            owner&.increment_field :secrets_burned unless owner&.anonymous?
            Onetime::Customer.secrets_burned.increment

            secret_logger.info 'Secret burned successfully',
              {
                secret_identifier: secret.shortid,
                receipt_identifier: receipt.identifier,
                owner_id: owner&.custid,
                user_id: cust&.custid,
                action: 'burn',
                result: :success,
              }
          else
            secret_logger.warn 'Burn failed - secret already consumed',
              {
                secret_identifier: secret.shortid,
                receipt_identifier: receipt.identifier,
                user_id: cust&.custid,
                action: 'burn',
                result: :already_consumed,
              }
          end

        elsif !correct_passphrase
          # Record failed attempt for rate limiting
          attempt_count = record_failed_passphrase_attempt!(potential_secret.identifier, passphrase_client_ip)

          secret_logger.warn 'Burn failed - incorrect passphrase',
            {
              receipt_identifier: receipt.identifier,
              secret_identifier: potential_secret.shortid,
              user_id: cust&.custid,
              action: 'burn',
              result: :passphrase_failed,
              attempt_count: attempt_count,
            }

          message = I18n.t('web.COMMON.error_passphrase', locale: locale, default: 'Incorrect passphrase')
          raise_form_error message

        end

        success_data
      end

      def success_data
        # Get base receipt attributes
        attributes = receipt.safe_dump

        # Resolve the domain for URL generation: use the custom domain
        # the secret was created on when available, otherwise canonical.
        domain     = if domains_enabled && !receipt.share_domain.to_s.empty?
                   receipt.share_domain
                 else
                   site_host
                 end
        domain_uri = [base_scheme, domain].join

        # Add required URL fields
        attributes.merge!(
          {
            # secret_state: 'burned',
            natural_expiration: natural_duration(receipt.default_expiration.to_i),
            expiration: (receipt.default_expiration.to_i + receipt.created.to_i),
            expiration_in_seconds: receipt.default_expiration.to_i,
            share_path: build_path(:secret, receipt.secret_identifier),
            burn_path: build_path(:receipt, receipt.identifier, 'burn'),
            receipt_path: build_path(:receipt, receipt.identifier),
            metadata_path: build_path(:receipt, receipt.identifier), # V2 backward-compat alias
            share_url: build_url(domain_uri, build_path(:secret, receipt.secret_identifier)),
            receipt_url: build_url(domain_uri, build_path(:receipt, receipt.identifier)),
            metadata_url: build_url(domain_uri, build_path(:receipt, receipt.identifier)), # V2 backward-compat alias
            burn_url: build_url(domain_uri, build_path(:receipt, receipt.identifier, 'burn')),
          },
        )

        {
          success: greenlighted,
          record: attributes,
          details: {
            type: 'record',
            title: 'Secret burned',
            display_lines: 0,
            display_feedback: false,
            no_cache: true,
            view_count: 0,
            has_passphrase: false,
            can_decrypt: false,
            show_secret: false,
            show_secret_link: false,
            show_receipt_link: false, # maintain public API
            show_receipt: true, # maintain public API
            show_recipients: !receipt.recipients.to_s.empty?,
            is_orphaned: false,
          },
        }
      end

      private

      # Client IP for the per-secret+IP passphrase rate-limit tier (M-8). Sourced
      # from strategy_result metadata (set for both anonymous and authenticated
      # callers). nil when unavailable, in which case the limiter falls back to
      # the global per-secret backstop rather than collapsing every caller into
      # one shared IP bucket. Do NOT use session['ip_address'] here -- it is
      # absent for the anonymous recipients who are the primary threat model.
      def passphrase_client_ip
        return unless respond_to?(:strategy_result)

        strategy_result&.metadata&.[](:ip)
      end
    end
  end
end
