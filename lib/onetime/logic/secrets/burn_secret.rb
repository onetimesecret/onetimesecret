module Onetime::Logic
  module Secrets

    class BurnSecret < OT::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :metadata, :secret, :correct_passphrase, :greenlighted

      def process_params
        @key = params[:key].to_s
        @metadata = Onetime::Metadata.load key
        @passphrase = params[:passphrase].to_s
        @continue = params[:continue] == true || params[:continue] == 'true'
      end

      def raise_concerns
        #limit_action :burn_secret
        raise OT::MissingSecret if metadata.nil?
      end

      require 'logger'

      def process
        logger = Logger.new(STDOUT)
        logger.level = Logger::DEBUG

        logger.debug("Starting process method")

        potential_secret = @metadata.load_secret
        logger.debug("Loaded potential secret: #{potential_secret.inspect}")

        if potential_secret
          @correct_passphrase = !potential_secret.has_passphrase? || potential_secret.passphrase?(passphrase)
          logger.debug("Correct passphrase: #{@correct_passphrase}")

          viewable = potential_secret.viewable?
          logger.debug("Secret viewable: #{viewable}")

          continue_result = params[:continue]
          logger.debug("Continue result: #{continue_result} #{continue_result.class}")

          @greenlighted = viewable && correct_passphrase && continue_result
          logger.debug("Greenlighted: #{@greenlighted}")

          if greenlighted
            @secret = potential_secret
            logger.debug("Secret set: #{@secret.inspect}")

            owner = secret.load_customer
            logger.debug("Loaded owner: #{owner.inspect}")

            secret.burned!
            logger.debug("Secret burned")

            owner.increment_field :secrets_burned unless owner.anonymous?
            logger.debug("Owner secrets burned incremented")

            OT::Customer.global.increment_field :secrets_burned
            logger.debug("Global secrets burned incremented")

            OT::Logic.stathat_count('Burned Secrets', 1)
            logger.debug("Stathat count incremented")

          elsif !correct_passphrase
            logger.debug("Incorrect passphrase")

            limit_action :failed_passphrase if !potential_secret.has_passphrase?
            logger.debug("Rate limit action taken")

            message = OT.locales.dig(locale, :web, :COMMON, :error_passphrase) || 'Incorrect passphrase'
            logger.debug("Error message: #{message}")

            raise_form_error message
          end
        end

        logger.debug("Process method completed")
      end
      def success_data
        {
          success: greenlighted,
          record: metadata.safe_dump,
          details: {}
        }
      end

    end

  end
end
