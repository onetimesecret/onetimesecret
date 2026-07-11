# lib/onetime/operations/email/provider_status.rb
#
# frozen_string_literal: true

require 'date'
require 'onetime/mail/feedback/ses'
require 'onetime/mail/feedback/lettermint'
require 'onetime/operations/email/error_scrub'

module Onetime
  module Operations
    module Email
      # Read the ACTIVE transport provider's deliverability status (Track B).
      #
      # Picks the provider via Mailer.determine_provider (one deployment runs one
      # transport — this is NOT a cross-provider matrix), builds the matching
      # feedback fetcher from Mailer.provider_credentials, and returns a
      # fail-soft Result. Only `ses` and `lettermint` are live providers (they
      # have a pull API); every other transport (logger/smtp/sendgrid/disabled)
      # returns capability=false.
      #
      # Fail-soft contract: this op MUST NEVER raise. Provider-determination,
      # fetcher construction (lazily memoized — it raises on the FIRST call, not
      # at .new), and the remote call are all wrapped. Any error → the degraded
      # payload (capability present, available=false + error note), never a 500
      # that takes down the colonel page. Mirrors the EmailSuppression fail-open
      # ethos.
      #
      # `fetcher:` is injectable (like SyncProviderFeedback's provider select) so
      # the SES/Lettermint mapping — the only part with real logic — is unit
      # testable without live credentials.
      class ProviderStatus
        # Providers with a pollable status API. Anything else → capability false.
        PROVIDERS = %w[ses lettermint].freeze

        # Fixed stats window (30 days). A selectable window (?days=) is deferred.
        WINDOW_DAYS = 30

        # SESv2 exposes no numeric bounce/complaint rate. A numeric rate would
        # require a new CloudWatch (AWS/SES Reputation.*) or SESv1
        # (GetSendStatistics) gem — an explicit, deferred gem-addition decision.
        # Tier is derived from enforcement_status + quota only meanwhile.
        SES_RATE_NOTE =
          'SESv2 exposes no numeric bounce/complaint rate; tier from enforcement_status + quota only.'

        # Marker set on the Lettermint block when /stats carries no complaint
        # field (its documented shape reports sent/delivered/bounced only). The
        # UI keys an i18n note off its presence, so "—" reads as "not reported".
        LETTERMINT_NO_COMPLAINTS_NOTE =
          'Lettermint /stats does not report complaints; complaint rate is unavailable.'

        Result = Data.define(:provider, :capability, :available, :error, :ses, :lettermint)

        def initialize(provider: nil, fetcher: nil)
          @provider = resolve_provider(provider)
          @fetcher  = fetcher
        end

        # @return [Result] always; never raises.
        def call
          return capability_false unless PROVIDERS.include?(@provider)

          case @provider
          when 'ses'        then ses_status
          when 'lettermint' then lettermint_status
          end
        rescue StandardError => ex
          degraded(ErrorScrub.scrub(ex))
        end

        private

        def resolve_provider(provider)
          (provider || Onetime::Mail::Mailer.determine_provider).to_s.downcase.strip
        rescue StandardError
          ''
        end

        def fetcher
          @fetcher ||= build_fetcher
        end

        def build_fetcher
          creds = Onetime::Mail::Mailer.provider_credentials(@provider)
          case @provider
          when 'ses'        then Onetime::Mail::Feedback::SES.new(creds)
          when 'lettermint' then Onetime::Mail::Feedback::Lettermint.new(creds)
          end
        end

        def ses_status
          data = fetcher.account_status
          Result.new(
            provider: @provider,
            capability: true,
            available: true,
            error: nil,
            ses: data.merge(
              rate_bounce: nil,
              rate_complaint: nil,
              rate_note: SES_RATE_NOTE,
            ),
            lettermint: nil,
          )
        rescue StandardError => ex
          degraded(ErrorScrub.scrub(ex))
        end

        def lettermint_status
          stats = fetcher.stats(from: window_from, to: window_to)
          sent  = stats[:sent].to_i

          Result.new(
            provider: @provider,
            capability: true,
            available: true,
            error: nil,
            ses: nil,
            lettermint: {
              window_days: WINDOW_DAYS,
              sent: sent,
              delivered: stats[:delivered].to_i,
              hard_bounced: stats[:hard_bounced].to_i,
              # nil (not 0) when Lettermint does not report complaints — the
              # fetcher preserves the distinction so the UI shows "not reported"
              # (—) rather than a misleading 0 count / 0.00% rate.
              spam_complaints: stats[:spam_complaints],
              opened: stats[:opened].to_i,
              clicked: stats[:clicked].to_i,
              # Rates computed in Ruby with float division; sent==0 AND a nil
              # numerator (complaints not reported) both guard to nil so the wire
              # never carries integer-division 0 or a NaN.
              rate_bounce: rate(stats[:hard_bounced], sent),
              rate_complaint: rate(stats[:spam_complaints], sent),
              # Signal (non-null) when Lettermint did not report complaints, so
              # the UI can explain the "—" complaint rate as "not reported"
              # rather than let an operator read it as zero.
              rate_note: (LETTERMINT_NO_COMPLAINTS_NOTE if stats[:spam_complaints].nil?),
            },
          )
        rescue StandardError => ex
          degraded(ErrorScrub.scrub(ex))
        end

        def rate(numerator, denominator)
          return nil if numerator.nil?
          return nil if denominator.to_i.zero?

          numerator.to_f / denominator.to_i
        end

        def window_from
          (Date.today - WINDOW_DAYS).strftime('%Y-%m-%d')
        end

        def window_to
          Date.today.strftime('%Y-%m-%d')
        end

        def capability_false
          Result.new(
            provider: @provider,
            capability: false,
            available: false,
            error: nil,
            ses: nil,
            lettermint: nil,
          )
        end

        def degraded(message)
          Result.new(
            provider: @provider,
            capability: true,
            available: false,
            error: message.to_s,
            ses: nil,
            lettermint: nil,
          )
        end
      end
    end
  end
end
