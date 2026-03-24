# apps/api/v1/logic/secrets/show_secret.rb
#
# frozen_string_literal: true

module V1::Logic
  module Secrets

    using Familia::Refinements::TimeLiterals

    # V1 compat: uses load_owner (not load_customer) and
    # decrypted_secret_value (not decrypted_value). The v0.24 model
    # renamed load_customer -> load_owner, and the new decryption
    # dispatcher (decrypted_secret_value) handles both v1 legacy
    # `value` field and v2 `ciphertext` field transparently.
    class ShowSecret < V1::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :secret, :show_secret, :secret_value, :is_truncated,
                  :original_size, :verification, :correct_passphrase,
                  :display_lines, :one_liner, :is_owner, :has_passphrase,
                  :secret_key, :share_domain

      def process_params
        @key = sanitize_identifier(params['key'].to_s)
        @secret = Onetime::Secret.load key
        @passphrase = params['passphrase'].to_s
        @continue = params['continue'].to_s == 'true'
      end

      def raise_concerns
        raise OT::MissingSecret if secret.nil? || !secret.viewable?
      end

      def process
        @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
        @show_secret = secret.viewable? && correct_passphrase && continue
        @verification = secret.verification.to_s == "true"
        @secret_key = @secret.identifier # Use identifier, not deprecated .key field

        owner = secret.load_owner

        if show_secret
          # Call decrypted_secret_value directly instead of guarding with
          # can_decrypt?. For passphrase-protected secrets, can_decrypt? checks
          # passphrase_temp which isn't set until decrypted_secret_value runs —
          # so can_decrypt? returns false and we fall through to secret.value
          # (which is empty for v0.24 ciphertext-only secrets). Since we've
          # already verified the passphrase is correct (line 35), we can safely
          # call decrypted_secret_value which handles both ciphertext (v2) and
          # legacy value paths.
          @secret_value = secret.decrypted_secret_value(passphrase_input: passphrase)
          @is_truncated = secret.truncated?
          @original_size = secret.respond_to?(:original_size) ? secret.original_size : nil

          if verification
            if owner.nil?
              raise_form_error "Unable to verify account"
            elsif cust.nil? || cust.anonymous? || (cust.custid == owner.custid && !owner.verified?)
              owner.verified! "true"
              # Skip for stateless auth (BasicAuth provides empty session)
              sess.clear unless sess.empty?
              secret.revealed!
            else
              raise_form_error "You can't verify an account when you're already logged in."
            end
          else

            owner.increment_field(:secrets_shared) if owner && !owner.anonymous?
            # TODO:
            # Onetime::Customer.global.increment_field :secrets_shared

            # Immediately mark the secret as revealed, so that it
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
            secret.revealed!

          end

        elsif continue && secret.has_passphrase? && !correct_passphrase

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

        secret.previewed! if secret.state?(:new)
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
