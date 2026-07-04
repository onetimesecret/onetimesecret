# apps/api/v2/logic/secrets/show_secret.rb
#
# frozen_string_literal: true

require 'onetime/security/passphrase_rate_limiter'

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # Show Secret
    #
    # @api Retrieves a secret's metadata and optionally its decrypted content.
    #   When called with continue=true and the correct passphrase, the secret
    #   value is returned and the secret is consumed. Without continue, returns
    #   only metadata such as whether a passphrase is required. The secret can
    #   only be viewed once.
    class ShowSecret < V2::Logic::Base
      include AccessTelemetry
      include Onetime::Logic::GuestRouteGating
      include Onetime::Security::PassphraseRateLimiter

      SCHEMAS = { response: 'secret' }.freeze

      attr_reader :identifier,
        :passphrase,
        :continue,
        :secret,
        :show_secret,
        :secret_value,
        :verification,
        :correct_passphrase,
        :display_lines,
        :one_liner,
        :is_owner,
        :has_passphrase,
        :secret_identifier,
        :share_domain

      def process_params
        @identifier = sanitize_identifier(params['identifier'].to_s)
        @secret     = Onetime::Secret.load identifier
        @passphrase = params['passphrase'].to_s
        @continue   = params['continue'].to_s == 'true'
      end

      def raise_concerns
        require_guest_route_enabled!(:show)
        require_entitlement!('api_access')
        raise OT::MissingSecret if secret.nil? || !secret.viewable?

        # Check passphrase rate limit before allowing passphrase attempts
        # This prevents brute-force attacks on secrets with passphrases
        check_passphrase_rate_limit!(secret.identifier) if secret.has_passphrase?
      end

      def process
        @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
        @show_secret        = secret.viewable? && correct_passphrase && continue
        @verification       = secret.verification.to_s == 'true'
        @secret_identifier  = @secret.identifier

        # Track passphrase attempts for rate limiting
        if secret.has_passphrase? && !passphrase.empty?
          if correct_passphrase
            # Clear rate limit on successful passphrase
            clear_passphrase_rate_limit!(secret.identifier)
          else
            # Record failed attempt
            record_failed_passphrase_attempt!(secret.identifier)
          end
        end

        if show_secret
          owner = secret.load_owner

          # verify_owner/reveal_secret return secret.reveal!, which decrypts and
          # returns the plaintext ONLY to the single caller that won the atomic
          # burn-after-reading claim; a losing request gets nil and never
          # computes the plaintext at all.
          @secret_value = if verification
                            verify_owner(owner)
                          else
                            reveal_secret(owner)
                          end

          # No plaintext means we did not win the reveal (a concurrent request
          # already consumed the secret): do not present it as viewable.
          @show_secret = false if @secret_value.nil?
        end

        resolve_share_domain
        @has_passphrase = secret.has_passphrase?
        @display_lines  = calculate_display_lines
        @is_owner       = secret.owner?(cust)
        @one_liner      = one_liner

        # Fetching metadata must not advance the secret's lifecycle state
        # (GET is a safe method, #3633); the access is recorded on the
        # receipt's timeline instead. Lifecycle now only moves on a genuine
        # reveal or burn.
        record_access_telemetry('secret_get')

        success_data
      end

      def success_data
        return nil unless secret

        ret = {
          record: secret.safe_dump,
          details: {
            continue: @continue,
            is_owner: @is_owner,
            show_secret: @show_secret,
            correct_passphrase: @correct_passphrase,
            display_lines: @display_lines,
            one_liner: @one_liner,
          },
        }

        # Add the secret_value only if the secret is viewable
        ret[:record][:secret_value] = secret_value if show_secret && secret_value

        ret
      end

      def one_liner
        return if secret_value.to_s.empty? # return nil when the value is empty

        secret_value.to_s.scan("\n").empty?
      end

      private

      def verify_owner(owner)
        if anonymous_user? || (cust.custid == owner.custid && !owner.verified?)
          owner.verified    = true
          owner.verified_by = 'email'
          owner.save
          # sess.clear wipes session data for this request. sess.destroy! does
          # not exist here — OT::Session wraps Rack::Session::Abstract::PersistedSecure,
          # which exposes no public destroy method. clear is the correct call.
          # Skip for stateless auth (BasicAuth provides empty session)
          sess.clear unless sess.empty?
          secret.reveal!(passphrase_input: passphrase)
        else
          raise_form_error "You can't verify an account when you're already logged in."
        end
      end

      # Reveal-and-consume the secret so it can't be shown again. If a network
      # failure prevents the client from receiving the response, we deliberately
      # cannot show it again -- a feature, not a bug.
      #
      # NOTE: reveal! is destructive and runs before the response is generated,
      # so every returned value must be plucked from the secret before this
      # point. It returns the plaintext ONLY to the caller that won the atomic
      # reveal claim; a request that lost the race gets nil, so the shared-secret
      # counters are gated on winning to avoid inflating them on a lost race.
      def reveal_secret(owner)
        plaintext = secret.reveal!(passphrase_input: passphrase)
        return plaintext if plaintext.nil?

        owner&.increment_field :secrets_shared unless owner&.anonymous?
        Onetime::Customer.secrets_shared.increment
        plaintext
      end

      def resolve_share_domain
        domain = if domains_enabled && !secret.share_domain.to_s.empty?
                   secret.share_domain
                 else
                   site_host
                 end

        @share_domain = [base_scheme, domain].join
      end

      def calculate_display_lines
        v   = secret_value.to_s
        ret = ((80 + v.size) / 80) + v.scan("\n").size + 3
        ret > 30 ? 30 : ret
      end
    end
  end
end
