


module Onetime::Logic
  module Secrets

    class BurnSecret < OT::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :metadata, :secret, :correct_passphrase, :greenlighted

      def process_params
        @key = params[:key].to_s
        @metadata = Onetime::Metadata.load key
        @passphrase = params[:passphrase].to_s
        @continue = params[:continue] == 'true'
      end

      def raise_concerns
        limit_action :burn_secret
        raise OT::MissingSecret if metadata.nil?
      end

      def process
        @secret = @metadata.load_secret
        if secret
          @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
          @greenlighted = secret.viewable? && correct_passphrase && continue
          owner = secret.load_customer
          if greenlighted

            owner.increment_field :secrets_burned unless owner.anonymous?
            OT::Customer.global.increment_field :secrets_burned

            secret.burned!

            OT::Logic.stathat_count('Burned Secrets', 1)
          elsif !correct_passphrase
            limit_action :failed_passphrase if secret.has_passphrase?
            # do nothing
          end
        end
      end

    end

  end
end
