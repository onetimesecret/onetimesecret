# lib/onetime/logic/secrets/show_secret.rb

module Onetime::Logic
  module Secrets

    class ShowSecret < OT::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :secret, :show_secret, :secret_value, :is_truncated,
                  :original_size, :verification, :correct_passphrase,
                  :display_lines, :one_liner, :is_owner, :has_passphrase,
                  :secret_key, :share_domain

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
        @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
        @show_secret = secret.viewable? && correct_passphrase && continue
        @verification = secret.verification.to_s == "true"
        @secret_key = @secret.key

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

            OT::Logic.stathat_count("Viewed Secrets", 1)
          end

        elsif continue && secret.has_passphrase? && !correct_passphrase
          limit_action :failed_passphrase
        end

        domain = if domains_enabled && !secret.share_domain.to_s.empty?
          secret.share_domain
        else
          site_host # via LogicHlpers#site_host
        end

        @share_domain = [base_scheme, domain].join
        @has_passphrase = secret.has_passphrase?
        @display_lines = calculate_display_lines
        @is_owner = secret.owner?(cust)
        @one_liner = one_liner

        secret.viewed! if secret.state?(:new)
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
