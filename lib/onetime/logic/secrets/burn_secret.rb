


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
        potential_secret = @metadata.load_secret
        if potential_secret
          @correct_passphrase = !potential_secret.has_passphrase? || potential_secret.passphrase?(passphrase)
          @greenlighted = potential_secret.viewable? && correct_passphrase && continue
          if greenlighted
            @secret = potential_secret

            owner = secret.load_customer
            secret.burned!

            owner.increment_field :secrets_burned unless owner.anonymous?

            OT::Customer.global.increment_field :secrets_burned

            OT::Logic.stathat_count('Burned Secrets', 1)

          elsif !correct_passphrase
            # If the passphrase is incorrect, we don't want to show the secret
            # obviously be we do want to count the attempt towards the rate limit.
            limit_action :failed_passphrase if !potential_secret.has_passphrase?

            message = OT.locales.dig(locale, :web, :COMMON, :error_passphrase) || 'Incorrect passphrase'
            raise_form_error message
          end
        end
      end

      def success_data
        {
          success: greenlighted,
          record: {
            metadata: metadata.safe_dump
          },
          details: {}
        }
      end

    end

  end
end
