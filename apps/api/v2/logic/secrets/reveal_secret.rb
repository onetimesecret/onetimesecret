# apps/api/v2/logic/secrets/reveal_secret.rb

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # Very similar logic to ShowSecret, but with a few key differences
    # as required by the v2 API. The v1 API uses the original ShowSecret.
    class RevealSecret < V2::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :identifier, :passphrase, :continue, :share_domain, :secret, :show_secret, :secret_value,
        :verification, :correct_passphrase, :display_lines, :one_liner, :is_owner, :has_passphrase, :secret_identifier

      def process_params
        @identifier = params['identifier'].to_s
        @secret     = Onetime::Secret.load identifier
        @passphrase = params['passphrase'].to_s
        @continue   = params['continue'].to_s == 'true'
      end

      def raise_concerns
        raise OT::MissingSecret if secret.nil? || !secret.viewable?
      end

      def process # rubocop:disable Metrics/PerceivedComplexity
        @correct_passphrase = secret.passphrase?(passphrase)
        @show_secret        = secret.viewable? && (correct_passphrase || !secret.has_passphrase?) && continue
        @verification       = secret.verification.to_s == 'true'
        @secret_identifier  = @secret.identifier
        @secret_shortid     = @secret.shortid

        secret_logger.debug 'Secret reveal initiated', {
          secret_identifier: secret.shortid,
          viewable: secret.viewable?,
          has_passphrase: secret.has_passphrase?,
          passphrase_correct: correct_passphrase,
          continue: continue,
          user_id: cust&.custid,
        }

        owner = secret.load_owner
        if show_secret

          # If we can't decrypt that's great! We just set secret_value to
          # the encrypted string.
          @secret_value = secret.ciphertext.reveal { it }

          if verification
            if owner.nil? || owner.anonymous? || owner.verified?
              secret_logger.error 'Invalid verification attempt', {
                secret_identifier: secret.shortid,
                owner_nil: owner.nil?,
                owner_anonymous: owner&.anonymous?,
                owner_verified: owner&.verified?,
                action: 'verification',
                result: :invalid,
              }
              secret.received!
              raise_form_error i18n.dig(:web, :COMMON, :verification_not_valid) || 'Verification not valid'

            elsif owner && (cust&.anonymous? || (cust&.custid == owner.custid && !owner.verified?))
              secret_logger.info 'Owner verification successful', {
                secret_identifier: secret.shortid,
                owner_id: owner.objid,
                action: 'verification',
                result: :verified,
              }
              owner.verified! 'true'
              owner.reset_secret.delete!
              sess.destroy!
              secret.received!

            else
              secret_logger.error 'Invalid verification - user already logged in', {
                secret_identifier: secret.shortid,
                user_id: cust&.custid,
                action: 'verification',
                result: :already_logged_in,
              }
              raise_form_error i18n.dig(:web, :COMMON,
                :verification_already_logged_in
              ) || 'Cannot verify when logged in'
            end
          else
            secret_logger.info 'Secret revealed successfully', {
              secret_identifier: secret.shortid,
              owner_id: owner&.objid,
              action: 'reveal',
              result: :success,
            }

            owner.increment_field :secrets_shared if !owner.nil? && !owner.anonymous?

            Onetime::Customer.secrets_shared.increment

            # Immediately mark the secret as viewed, so that it
            # can't be shown again. If there's a network failure
            # that prevents the client from receiving the response,
            # we're not able to show it again. This is a feature
            # not a bug.
            #
            # NOTE: This destructive action is called before the
            # response is returned or even fully generated (which
            # happens in success_data). This is a feature, not a
            # bug but it means that all return values need to be
            # pluck out of the secret object before this is called.
            secret.received!

          end

        elsif secret.has_passphrase? && !correct_passphrase
          secret_logger.warn 'Incorrect passphrase attempt', {
            secret_identifier: secret.shortid,
            user_id: cust&.custid,
            session_id: sess&.sessid,
            action: 'reveal',
            result: :passphrase_failed,
          }

          message = i18n.dig(:web, :COMMON, :incorrect_passphrase) || 'Incorrect passphrase'
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
    end
  end
end
