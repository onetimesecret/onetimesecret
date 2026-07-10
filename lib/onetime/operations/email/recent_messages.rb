# lib/onetime/operations/email/recent_messages.rb
#
# frozen_string_literal: true

require 'onetime/mail/feedback/lettermint'
require 'onetime/operations/email/error_scrub'

module Onetime
  module Operations
    module Email
      # Recent outbound message log for the active transport (Track B, item 9).
      #
      # Only Lettermint has a per-message API. SES is fire-and-forget with NO
      # per-message list — so on SES (and every non-live transport) this returns
      # capability=false and an empty page. We do NOT invent a local send log;
      # the epic's send-time event log is explicitly out of scope. The log is
      # sourced from the provider's OWN message API.
      #
      # Fail-soft: a Lettermint timeout/error → capability=true, available=false,
      # empty messages, error note. Never a 500.
      #
      # `fetcher:` is injectable for unit testing without live credentials.
      class RecentMessages
        Result = Data.define(
          :provider, :capability, :available, :error, :messages, :pagination
        )

        def initialize(provider: nil, page: 1, per_page: 30, cursor: nil, fetcher: nil)
          @provider = resolve_provider(provider)
          @page     = page.to_i
          @per_page = per_page.to_i
          @cursor   = cursor
          @fetcher  = fetcher
        end

        # @return [Result] always; never raises.
        def call
          # Only Lettermint exposes a message list; SES + every other transport
          # surface capability=false (structural, not a runtime failure).
          return capability_false unless @provider == 'lettermint'

          result = fetcher.messages(page_size: @per_page, page_cursor: @cursor)
          Result.new(
            provider: @provider,
            capability: true,
            available: true,
            error: nil,
            messages: result[:messages],
            pagination: {
              page: @page,
              per_page: @per_page,
              # Lettermint is cursor-paginated — no server-side totals. Frontend
              # uses `cursor` for "next", not a page count.
              total_count: nil,
              total_pages: nil,
              cursor: result[:cursor],
            },
          )
        rescue StandardError => ex
          degraded(ErrorScrub.scrub(ex))
        end

        private

        def capability_false
          Result.new(
            provider: @provider,
            capability: false,
            available: false,
            error: nil,
            messages: [],
            pagination: {
              page: @page,
              per_page: @per_page,
              total_count: 0,
              total_pages: 0,
              cursor: nil,
            },
          )
        end

        def degraded(message)
          Result.new(
            provider: @provider,
            capability: true,
            available: false,
            error: message.to_s,
            messages: [],
            pagination: {
              page: @page,
              per_page: @per_page,
              total_count: 0,
              total_pages: 0,
              cursor: nil,
            },
          )
        end

        def resolve_provider(provider)
          (provider || Onetime::Mail::Mailer.determine_provider).to_s.downcase.strip
        rescue StandardError
          ''
        end

        def fetcher
          @fetcher ||= Onetime::Mail::Feedback::Lettermint.new(
            Onetime::Mail::Mailer.provider_credentials(@provider),
          )
        end
      end
    end
  end
end
