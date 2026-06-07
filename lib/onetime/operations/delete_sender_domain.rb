# lib/onetime/operations/delete_sender_domain.rb
#
# frozen_string_literal: true

require_relative '../mail/sender_strategies'

module Onetime
  module Operations
    # Deletes a sender domain from the mail provider (currently Lettermint).
    # Extracted from RemoveDomain and DeleteSenderConfig for reuse.
    #
    # Never raises — all errors are wrapped in the Result.
    # Callers can fire-and-forget: domain/config removal proceeds regardless.
    #
    #   result = DeleteSenderDomain.new(mailer_config: config).call
    #   result.success?  # => true/false
    #
    class DeleteSenderDomain
      include Onetime::LoggerMethods

      Result = Data.define(:success, :message, :error) do
        def success? = success == true
        def failed? = !success?
      end

      # @param mailer_config [CustomDomain::MailerConfig, nil]
      def initialize(mailer_config:)
        @mailer_config = mailer_config
      end

      def call
        return skipped('no mailer config') unless @mailer_config
        return skipped('not a lettermint provider') unless @mailer_config.effective_provider == 'lettermint'

        credentials = Onetime::Mail::Mailer.provider_credentials('lettermint')
        strategy    = Onetime::Mail::SenderStrategies.for_provider('lettermint')
        result      = strategy.delete_sender_identity(@mailer_config, credentials: credentials)

        logger.info 'Sender domain deleted',
          domain_id: @mailer_config.domain_id,
          message: result[:message]

        Result.new(success: true, message: result[:message], error: nil)
      rescue StandardError => ex
        logger.error 'Sender domain deletion failed',
          domain_id: @mailer_config&.domain_id,
          error: ex.message,
          error_class: ex.class.name
        Result.new(success: false, message: nil, error: ex.message)
      end

      private

      def skipped(reason)
        Result.new(success: true, message: "skipped: #{reason}", error: nil)
      end

      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end
