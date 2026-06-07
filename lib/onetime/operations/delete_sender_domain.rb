# lib/onetime/operations/delete_sender_domain.rb
#
# frozen_string_literal: true

require_relative '../mail/sender_strategies'

module Onetime
  module Operations
    # Deletes a sender domain from its mail provider.
    # Extracted from RemoveDomain and DeleteSenderConfig for reuse.
    #
    # Dispatches on the mailer config's effective_provider, so each
    # provider's sender identity is torn down through its own strategy
    # (SES, SendGrid, Lettermint). SMTP is a no-op — there is no remote
    # sender identity to delete.
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

        provider = resolve_provider
        return skipped('no effective provider') if provider.empty?

        credentials = Onetime::Mail::Mailer.provider_credentials(provider)
        strategy    = Onetime::Mail::SenderStrategies.for_provider(provider)
        result      = strategy.delete_sender_identity(@mailer_config, credentials: credentials)

        logger.info 'Sender domain deleted',
          domain_id: @mailer_config.domain_id,
          provider: provider,
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

      # Resolve the provider to dispatch sender-identity deletion to.
      #
      # Prefers the mailer config's effective_provider (which itself
      # falls back to the installation-level sender provider). When that
      # is unresolvable, default to 'lettermint' for back-compat with
      # configs created before the `provider` field existed — but only
      # when a from_address remains to tear down. Returns an empty
      # string when there is nothing to act on.
      #
      # @return [String] Lowercased provider name, or '' when unresolvable
      def resolve_provider
        provider = @mailer_config.effective_provider.to_s.strip.downcase
        return provider unless provider.empty?

        @mailer_config.from_address.to_s.strip.empty? ? '' : 'lettermint'
      end

      def skipped(reason)
        Result.new(success: true, message: "skipped: #{reason}", error: nil)
      end

      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end
