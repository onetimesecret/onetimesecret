# apps/api/v2/logic/secrets/show_secret.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class ShowSecret < V2::Logic::Base
      attr_reader :identifier, :passphrase, :continue, :secret, :show_secret, :secret_value,
        :verification, :correct_passphrase, :display_lines, :one_liner,
        :is_owner, :has_passphrase, :secret_identifier, :share_domain

      def process_params
        @identifier = params['identifier'].to_s
        @secret     = Onetime::Secret.load identifier
        @passphrase = params['passphrase'].to_s
        @continue   = params['continue'].to_s == 'true'
      end

      def raise_concerns
        raise OT::MissingSecret if secret.nil? || !secret.viewable?
      end

      def process
        @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
        @show_secret        = secret.viewable? && correct_passphrase && continue
        @verification       = secret.verification.to_s == 'true'
        @secret_identifier  = @secret.identifier

        owner = secret.load_owner

        if show_secret
          # If we can't decrypt that's great! We just set secret_value to
          # the encrypted string.
          @secret_value = secret.ciphertext.reveal { it }

          if verification
            if cust.anonymous? || (cust.custid == owner.custid && !owner.verified?)
              owner.verified! 'true'
              sess.destroy!
              secret.received!
            else
              raise_form_error "You can't verify an account when you're already logged in."
            end
          else

            owner.increment_field :secrets_shared unless owner.anonymous?
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

        elsif continue && secret.has_passphrase? && !correct_passphrase

        end

        domain = if domains_enabled && !secret.share_domain.to_s.empty?
                   secret.share_domain
                 else
                   site_host # via LogicHlpers#site_host
                 end

        @share_domain   = [base_scheme, domain].join
        @has_passphrase = secret.has_passphrase?
        @display_lines  = calculate_display_lines
        @is_owner       = secret.owner?(cust)
        @one_liner      = one_liner

        secret.viewed! if secret.state?(:new)

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
