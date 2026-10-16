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
    # sender identity to delete. Configs that resolve to no provider, or
    # to a transport without a sender strategy (e.g. 'logger'), are
    # skipped rather than treated as errors.
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

        # effective_provider is the single source of truth: it returns the
        # config's provider, or the installation default, already normalized.
        # Legacy configs predating the provider field resolve correctly here
        # via that installation-level fallback.
        provider = @mailer_config.effective_provider.to_s
        return skipped('no effective provider', provider: provider) if provider.empty?
        return skipped("unsupported provider '#{provider}'", provider: provider) unless
          Onetime::Mail::SenderStrategies.supported?(provider)

        credentials = Onetime::Mail::Mailer.provider_credentials(provider)
        strategy    = Onetime::Mail::SenderStrategies.for_provider(provider)
        result      = strategy.delete_sender_identity(@mailer_config, credentials: credentials)

        validate_deletion_result!(result)

        context = {
          domain_id: @mailer_config.domain_id,
          provider: provider,
          outcome: result[:outcome],
          message: result[:message],
        }
        case result[:outcome]
        when :failed
          logger.error 'Sender domain deletion failed', **context, error: result[:error]
          return Result.new(success: false, message: result[:message], error: result[:error])
        when :deleted
          logger.info 'Sender domain deleted', **context
        when :absent
          logger.info 'Sender domain already absent', **context
        when :skipped
          logger.info 'Sender domain deletion skipped (no-op)', **context
        end

        Result.new(success: true, message: result[:message], error: nil)
      rescue StandardError => ex
        error = ex.message.to_s
        error = ex.class.to_s if error.strip.empty?
        logger.error 'Sender domain deletion failed',
          domain_id: @mailer_config&.domain_id,
          provider: provider,
          outcome: :failed,
          error: error,
          error_class: ex.class.name
        Result.new(success: false, message: nil, error: error)
      end

      private

      def validate_deletion_result!(result)
        unless result.is_a?(Hash) && [:outcome, :deleted, :message, :error].all? { |key| result.key?(key) }
          raise ArgumentError, 'Invalid sender deletion result: expected a hash with outcome, deleted, message, and error'
        end
        unless [:deleted, :absent, :skipped, :failed].include?(result[:outcome])
          raise ArgumentError, 'Invalid sender deletion result: unknown outcome'
        end
        unless result[:deleted] == (result[:outcome] == :deleted)
          raise ArgumentError, 'Invalid sender deletion result: deleted contradicts outcome'
        end
        unless nonempty_string?(result[:message])
          raise ArgumentError, 'Invalid sender deletion result: message must be a nonempty string'
        end

        valid_error = result[:outcome] == :failed ? nonempty_string?(result[:error]) : result[:error].nil?
        raise ArgumentError, 'Invalid sender deletion result: error contradicts outcome' unless valid_error
      end

      def nonempty_string?(value)
        value.is_a?(String) && !value.strip.empty?
      end

      def skipped(reason, provider: nil)
        message = "skipped: #{reason}"
        logger.info 'Sender domain deletion skipped (no-op)',
          domain_id: @mailer_config&.domain_id,
          provider: provider,
          outcome: :skipped,
          message: message
        Result.new(success: true, message: message, error: nil)
      end

      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end
