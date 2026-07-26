# apps/api/v2/logic/secrets/reveal_secret.rb
#
# frozen_string_literal: true

require 'onetime/security/passphrase_rate_limiter'

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # Reveal Secret
    #
    # @api Retrieves and permanently reveals a secret's content. Requires
    #   the secret identifier, a passphrase if one was set, and a continue
    #   flag to confirm the reveal. The secret is destroyed immediately
    #   upon reveal and cannot be accessed again. Returns the decrypted
    #   secret value along with display metadata.
    #
    # Very similar logic to ShowSecret, but with a few key differences
    # as required by the v2 API. The v1 API uses the original ShowSecret.
    #
    # NOTE: As a general rule, it is bad "form" (no pun intended) to raise an
    # http error response during the reveal flow unless it is necessary like
    # in the case of a secret that doesn't exist or when there's a passphrase
    # and it was entered incorrectly. When the value is included in the payload
    # and the response is anything but a 2xx, the UI won't display it; it'll
    # revert to the Click to Reveal UI, which will then continue to show an
    # error since the secret will have been expunged by that point. Then it's
    # not until a hard refresh that the backend responds with a 404 for the
    # page itself. It's confusing and even worse it loses the secret.
    #
    class RevealSecret < V2::Logic::Base
      include Onetime::LoggerMethods
      include Onetime::Logic::GuestRouteGating
      include Onetime::Security::PassphraseRateLimiter
      include ActorAttribution

      SCHEMAS = { response: 'secret' }.freeze

      attr_reader :identifier,
        :passphrase,
        :continue,
        :share_domain,
        :secret,
        :show_secret,
        :secret_value,
        :verification,
        :correct_passphrase,
        :display_lines,
        :one_liner,
        :is_owner,
        :has_passphrase,
        :secret_identifier

      def process_params
        @identifier = sanitize_identifier(params['identifier'])
        @secret     = Onetime::Secret.load identifier
        @passphrase = params['passphrase'].to_s
        @continue   = params['continue'].to_s == 'true'
      end

      def raise_concerns
        require_guest_route_enabled!(:reveal)
        require_entitlement!('api_access')
        raise OT::MissingSecret if secret.nil? || !secret.viewable?

        # C10 fast-fail: when the boot-time verifier says the running SECRET
        # does not match this datastore, no decrypt can succeed — fail before
        # any reveal claim so no secret pays for the diagnosis. Gated on
        # continue (the reveal-intent signal) so metadata-only requests keep
        # answering; the claim rollback in Secret#reveal! is the backstop.
        raise Onetime::SecretUndecryptable if continue && Onetime.secret_verifier_state == :mismatch

        # Check passphrase rate limit before allowing passphrase attempts
        # This prevents brute-force attacks on secrets with passphrases
        check_passphrase_rate_limit!(secret.identifier, passphrase_client_ip) if secret.has_passphrase?
      end

      def process # rubocop:disable Metrics/PerceivedComplexity
        @correct_passphrase = secret.passphrase?(passphrase)
        @show_secret        = secret.viewable? && (correct_passphrase || !secret.has_passphrase?) && continue
        @verification       = secret.verification.to_s == 'true'
        @secret_identifier  = @secret.identifier
        @secret_shortid     = @secret.shortid

        secret_logger.debug 'Secret reveal initiated',
          {
            secret_identifier: secret.shortid,
            viewable: secret.viewable?,
            has_passphrase: secret.has_passphrase?,
            passphrase_correct: correct_passphrase,
            continue: continue,
            user_id: cust&.custid,
          }

        owner = secret.load_owner
        if show_secret
          # Compute the actor attribution BEFORE reveal! consumes the secret:
          # owner?(cust) reads the still-in-memory owner_id. Threaded into every
          # reveal! path below so the 'revealed' audit event records who acted
          # (#3639). The anonymous guard lives in lifecycle_actor_context.
          actor_context = lifecycle_actor_context(secret)

          # Clear any rate limit state on successful passphrase entry
          clear_passphrase_rate_limit!(secret.identifier, passphrase_client_ip) if secret.has_passphrase?

          # Decryption is deferred to secret.reveal! below: it decrypts ONLY on
          # the caller that wins the atomic reveal claim, so a request that lost
          # the burn-after-reading race never even computes the plaintext.

          if verification

            if owner.nil?
              secret_logger.error 'Invalid verification attempt - owner not found',
                {
                  secret_identifier: secret.shortid,
                  action: 'verification',
                  result: :invalid,
                }
              # Do not mark as received obviously
              raise_form_error I18n.t('web.COMMON.verification_not_valid', locale: @locale, default: 'Verification not valid')
            elsif owner&.anonymous?
              secret_logger.error 'Invalid verification attempt - owner anonymous',
                {
                  secret_identifier: secret.shortid,
                  action: 'verification',
                  result: :invalid,
                }
              # Do not mark as received for an anonymous soul. How did we
              # even get here? It means a verification secret for authentication_mode=basic
              # has a nil or invalid object identifier for the owner.
              raise_form_error I18n.t('web.COMMON.verification_not_valid', locale: @locale, default: 'Verification not valid')
            elsif owner.verified?
              secret_logger.error 'Invalid verification attempt - owner already verified',
                {
                  secret_identifier: secret.shortid,
                  action: 'verification',
                  result: :invalid,
                }
              # This bloke was already verified. How did we get here? Who sent
              # multiple verification secrets? Or who sent a verification secret
              # even though the account was already verified?
              #
              # In any case, we logged it as an error but reveal the secret
              # (which updates the receipt record and then expunges the secret
              # record) and allow the user to carry on. reveal! returns the
              # plaintext only if this caller won the one-shot claim.
              @secret_value = secret.reveal!(passphrase_input: @passphrase, actor_context: actor_context)

            elsif owner && (cust&.anonymous? || (cust&.custid == owner.custid && !owner.verified?))
              secret_logger.info 'Owner verification successful',
                {
                  secret_identifier: secret.shortid,
                  owner_id: owner.objid,
                  action: 'verification',
                  result: :verified,
                }
              owner.verified    = true
              owner.verified_by = 'email'  # Track email verification method
              owner.save
              owner.reset_secret.delete!
              # Skip for stateless auth (BasicAuth provides empty session)
              sess.clear unless sess.empty?
              @secret_value     = secret.reveal!(passphrase_input: @passphrase, actor_context: actor_context)

            else
              secret_logger.error 'Invalid verification - user already logged in',
                {
                  secret_identifier: secret.shortid,
                  user_id: cust&.custid,
                  action: 'verification',
                  result: :already_logged_in,
                }
              raise_form_error I18n.t(
                'web.COMMON.verification_already_logged_in',
                locale: @locale,
                default: 'Cannot verify when logged in',
              )
            end
          else
            # Reveal-and-consume the secret so it can't be shown again. If a
            # network failure prevents the client from receiving the response,
            # we deliberately cannot show it again -- a feature, not a bug.
            # reveal! is destructive and runs before the response is generated,
            # so every returned value must be plucked from the secret first.
            #
            # reveal! returns the plaintext ONLY to the caller that won the
            # atomic claim; a request that lost the burn-after-reading race gets
            # nil. The success log and the shared-secret counters are therefore
            # gated on winning, so a losing request neither claims success nor
            # inflates the metrics.
            @secret_value = secret.reveal!(passphrase_input: @passphrase, actor_context: actor_context)

            if @secret_value
              secret_logger.info 'Secret revealed successfully',
                {
                  secret_identifier: secret.shortid,
                  owner_id: owner&.objid,
                  action: 'reveal',
                  result: :success,
                }

              owner.increment_field :secrets_shared if !owner.nil? && !owner.anonymous?
              Onetime::Customer.secrets_shared.increment
            end
          end

          # No plaintext means we did not win the reveal (a concurrent request
          # already consumed the secret): do not present it as viewable.
          @show_secret = false if @secret_value.nil?

        elsif secret.has_passphrase? && !correct_passphrase
          # Record failed attempt for rate limiting
          attempt_count = record_failed_passphrase_attempt!(secret.identifier, passphrase_client_ip)

          secret_logger.warn 'Incorrect passphrase attempt',
            {
              secret_identifier: secret.shortid,
              user_id: cust&.custid,
              session_id: safe_session_id&.public_id,
              action: 'reveal',
              result: :passphrase_failed,
              attempt_count: attempt_count,
            }

          message = I18n.t('web.COMMON.incorrect_passphrase', locale: @locale, default: 'Incorrect passphrase')
          raise_form_error message
        end

        domain = if domains_enabled
                   if secret.share_domain.to_s.empty?
                     site_host
                   else
                     secret.share_domain
                   end
                 else
                   site_host
                 end

        @share_domain   = [base_scheme, domain].join
        @is_owner       = @secret.owner?(cust)
        @has_passphrase = @secret.has_passphrase?
        @display_lines  = calculate_display_lines
        @one_liner      = one_liner

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

      def calculate_display_lines
        v   = secret_value.to_s
        ret = ((80 + v.size) / 80) + v.scan("\n").size + 3
        ret > 30 ? 30 : ret
      end

      def one_liner
        return if secret_value.to_s.empty? # return nil when the value is empty

        secret_value.to_s.scan("\n").empty?
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
