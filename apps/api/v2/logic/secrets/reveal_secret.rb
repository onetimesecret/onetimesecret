# apps/api/v2/logic/secrets/reveal_secret.rb

module V2::Logic
  module Secrets
    # Very similar logic to ShowSecret, but with a few key differences
    # as required by the v2 API. The v1 API uses the original ShowSecret.
    class RevealSecret < V2::Logic::Base
      attr_reader :key, :passphrase, :continue, :share_domain, :secret, :show_secret, :secret_value, :is_truncated, :verification, :correct_passphrase, :display_lines, :one_liner, :is_owner, :has_passphrase, :secret_key

      def process_params
        @key        = params[:key].to_s
        @secret     = V2::Secret.load key
        @passphrase = params[:passphrase].to_s
        @continue   = params[:continue].to_s == 'true'
      end

      def raise_concerns
        limit_action :show_secret
        raise OT::MissingSecret if secret.nil? || !secret.viewable?
      end

      def process # rubocop:disable Metrics/MethodLength,Metrics/PerceivedComplexity
        @correct_passphrase = secret.passphrase?(passphrase)
        @show_secret        = secret.viewable? && (correct_passphrase || !secret.has_passphrase?) && continue
        @verification       = secret.verification.to_s == 'true'
        @secret_key         = @secret.key
        @secret_shortkey    = @secret.shortkey

        OT.ld "[reveal_secret] secret=#{secret.shortkey} viewable=#{secret.viewable?} correct_passphrase=#{correct_passphrase} continue=#{continue}"

        owner = secret.load_customer
        if show_secret

          # If we can't decrypt that's great! We just set secret_value to
          # the encrypted string.
          @secret_value = secret.can_decrypt? ? secret.decrypted_value : secret.value
          @is_truncated = secret.truncated?

          if verification
            if owner.nil? || owner.anonymous? || owner.verified?
              OT.le "[verification] Invalid verification attempt for secret #{secret.shortkey} - no owner or anonymous owner or already verified"
              secret.received!
              raise_form_error i18n.dig(:web, :COMMON, :verification_not_valid) || 'Verification not valid'

            elsif cust.anonymous? || (cust.custid == owner.custid && !owner.verified?)
              OT.li "[verification] Verifying owner #{owner.custid} for secret #{secret.shortkey}"
              owner.verified! 'true'
              owner.reset_secret.delete!
              sess.destroy!
              secret.received!

            else
              OT.le '[verification] Invalid verification - user already logged in'
              raise_form_error i18n.dig(:web, :COMMON,
                :verification_already_logged_in) || 'Cannot verify when logged in'
            end
          else
            OT.li "[reveal_secret] #{secret.key} viewed successfully"
            owner.increment_field :secrets_shared unless owner.anonymous?
            V2::Customer.global.increment_field :secrets_shared

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

            V2::Logic.stathat_count('Viewed Secrets', 1)
          end

        elsif secret.has_passphrase? && !correct_passphrase
          OT.le "[reveal_secret] Failed passphrase attempt for secret #{secret.shortkey} #{sess.short_identifier} #{sess.ipaddress}"
          limit_action :failed_passphrase if secret.has_passphrase?
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
        if show_secret && secret_value
          ret[:record][:secret_value] = secret_value
        end

        ret
      end

      def calculate_display_lines
        v   = secret_value.to_s
        ret = ((80+v.size)/80) + (v.scan("\n").size) + 3
        ret > 30 ? 30 : ret
      end

      def one_liner
        return if secret_value.to_s.empty? # return nil when the value is empty

        secret_value.to_s.scan("\n").empty?
      end
    end
  end
end
