# lib/onetime/operations/email/recipient_lookup.rb
#
# frozen_string_literal: true

require 'onetime/models/email_suppression'
require 'onetime/mail/feedback/ses'
require 'onetime/mail/feedback/lettermint'
require 'onetime/operations/email/error_scrub'

module Onetime
  module Operations
    module Email
      # Look up ONE recipient address across BOTH the local suppression store and
      # the live active-transport provider (Track B, item 10).
      #
      # The local store (EmailSuppression) is always readable — it is the
      # authority and is returned even when the provider read fails. The provider
      # read is fail-soft: a timeout/auth error → provider_result nil +
      # available=false; a provider "not found" (SES NotFoundException, Lettermint
      # empty) is NOT an error — it is provider_result.suppressed=false,
      # available=true.
      #
      # Normalization: the address is keyed via EmailSuppression.normalize
      # (strip.downcase) for BOTH the local read and the value handed to the
      # provider. FORBIDDEN: OT::Utils.normalize_email / EmailHash (NFC +
      # downcase(:fold)) — it would not match the stored suppression keys and
      # every lookup would silently miss.
      #
      # `fetcher:` is injectable for unit testing without live credentials.
      class RecipientLookup
        PROVIDERS = %w[ses lettermint].freeze

        Result = Data.define(
          :address, :provider, :capability, :available, :error, :local, :provider_result
        )

        def initialize(address:, provider: nil, fetcher: nil)
          @address  = Onetime::EmailSuppression.normalize(address)
          @provider = resolve_provider(provider)
          @fetcher  = fetcher
        end

        # @return [Result] always; never raises.
        def call
          local = local_status # local store is ALWAYS readable + authoritative

          unless PROVIDERS.include?(@provider)
            return Result.new(
              address: @address,
              provider: @provider,
              capability: false,
              available: false,
              error: nil,
              local: local,
              provider_result: nil,
            )
          end

          provider_lookup(local)
        end

        private

        def provider_lookup(local)
          result = fetcher.lookup(@address)
          Result.new(
            address: @address,
            provider: @provider,
            capability: true,
            available: true,
            error: nil,
            local: local,
            provider_result: {
              suppressed: result[:suppressed] == true,
              reason: result[:reason],
              last_update_time: result[:last_update_time],
            },
          )
        rescue StandardError => ex
          # Fail-soft: local stays authoritative, provider_result nil.
          Result.new(
            address: @address,
            provider: @provider,
            capability: true,
            available: false,
            error: ErrorScrub.scrub(ex),
            local: local,
            provider_result: nil,
          )
        end

        def local_status
          entry = Onetime::EmailSuppression.lookup(@address)
          if entry
            {
              suppressed: true,
              reason: entry['reason'].to_s,
              source: entry['source'].to_s,
              created: entry['created'].to_i,
            }
          else
            { suppressed: false, reason: nil, source: nil, created: nil }
          end
        end

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
      end
    end
  end
end
