


module Onetime::Logic
  module Secrets

    class ShowSecret < OT::Logic::Base
      attr_reader :key, :passphrase, :continue, :share_domain
      attr_reader :secret, :show_secret, :secret_value, :truncated, :original_size, :verification, :correct_passphrase
      def process_params
        @key = params[:key].to_s
        @secret = Onetime::Secret.load key
        @passphrase = params[:passphrase].to_s
        @continue = params[:continue] == 'true'
      end
      def raise_concerns
        limit_action :show_secret
        raise OT::MissingSecret if secret.nil? || !secret.viewable?
      end
      def process
        @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
        @show_secret = secret.viewable? && correct_passphrase && continue
        @verification = secret.verification.to_s == "true"
        @share_domain = secret.share_domain

        owner = secret.load_customer

        if show_secret
          @secret_value = secret.can_decrypt? ? secret.decrypted_value : secret.value
          @truncated = secret.truncated?
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

            owner.increment_field :secrets_shared unless cust.anonymous?
            OT::Customer.global.increment_field :secrets_shared

            secret.received!

            OT::Logic.stathat_count("Viewed Secrets", 1)
          end
        elsif !correct_passphrase
          limit_action :failed_passphrase if secret.has_passphrase?
          # do nothing
        end
      end
    end


  end
end
