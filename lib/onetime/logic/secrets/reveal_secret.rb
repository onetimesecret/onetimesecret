


module Onetime::Logic
  module Secrets

    # Very similar logic to ShowSecret, but with a few key differences
    # as required by the v2 API. The v1 API uses the original ShowSecret.
    class RevealSecret < OT::Logic::Base
      attr_reader :key, :passphrase, :continue, :share_domain
      attr_reader :secret, :show_secret, :secret_value, :is_truncated,
                  :original_size, :verification, :correct_passphrase,
                  :display_lines, :one_liner, :is_owner, :has_passphrase,
                  :secret_key

      def process_params
        @key = params[:key].to_s
        @secret = Onetime::Secret.load key
        @passphrase = params[:passphrase].to_s
        @continue = params[:continue].to_s == 'true'
      end

      def raise_concerns
        limit_action :show_secret
        raise OT::MissingSecret if secret.nil? || !secret.viewable?
      end

      def process
        @correct_passphrase = secret.has_passphrase? && secret.passphrase?(passphrase)
        @show_secret = secret.viewable? && (correct_passphrase || !secret.has_passphrase?) && continue
        @verification = secret.verification.to_s == "true"
        @secret_key = @secret.key
        @secret_shortkey = @secret.shortkey

        owner = secret.load_customer

        if show_secret
          # If we can't decrypt that's great! We just set secret_value to
          # the encrypted string.
          @secret_value = secret.can_decrypt? ? secret.decrypted_value : secret.value
          @is_truncated = secret.truncated?
          @original_size = secret.original_size

          if verification
            if cust.anonymous? || (cust.custid == owner.custid && !owner.verified?)
              owner.verified! "true"
              sess.destroy!
              secret.received!
            else
              raise_form_error "You can't verify an account when you're already logged in."
            end
          else

            owner.increment_field :secrets_shared unless owner.anonymous?
            OT::Customer.global.increment_field :secrets_shared

            secret.received!

            OT::Logic.stathat_count("Viewed Secrets", 1)
          end

        elsif secret.has_passphrase? && !correct_passphrase
          limit_action :failed_passphrase if secret.has_passphrase?
          message = OT.locales.dig(locale, :web, :COMMON, :error_passphrase) || 'Incorrect passphrase'
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

        @share_domain = [base_scheme, domain].join
        @is_owner = @secret.owner?(cust)
        @has_passphrase = @secret.has_passphrase?
        @display_lines = calculate_display_lines
        @one_liner = one_liner
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
            one_liner: @one_liner
          }
        }

        # Add the secret_value only if the secret is viewable
        if show_secret && secret_value
          ret[:record][:secret_value] = secret_value
        end

        ret
      end

      def calculate_display_lines
        v = secret_value.to_s
        ret = ((80+v.size)/80) + (v.scan(/\n/).size) + 3
        ret = ret > 30 ? 30 : ret
      end

      def one_liner
        return if secret_value.to_s.empty? # return nil when the value is empty
        secret_value.to_s.scan(/\n/).size.zero?
      end
    end

  end
end
