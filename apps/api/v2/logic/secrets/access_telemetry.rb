# apps/api/v2/logic/secrets/access_telemetry.rb
#
# frozen_string_literal: true

require 'onetime/security/request_context'

module V2::Logic
  module Secrets
    # Records secret accesses on the receipt's access timeline
    # (Receipt::Features::AccessTimeline) from the read endpoints.
    #
    # This replaces the old pattern of advancing the secret's lifecycle state
    # (`previewed!`) as a side effect of a GET (#3633): the lifecycle field
    # now only moves on a genuine reveal or burn, while "the link was
    # fetched" is captured as append-only telemetry the creator can see.
    module AccessTelemetry
      private

      # Best-effort by design: telemetry must never break or delay the read
      # path, so every failure is logged and swallowed. Secrets without a
      # receipt (e.g. account-verification secrets) are skipped.
      #
      # Creator self-access is a DISTINCT signal from third-party access
      # (a creator opening their own link is not "the recipient saw it").
      # The creator opening their own secret *link* is the "previewed" event
      # (creator-facing term; #3633): it is what the receipt page surfaces as
      # "you previewed this secret". Other creator self-accesses keep the
      # 'creator_' prefix (e.g. 'creator_status_get'), and third-party fetches
      # stay 'secret_get' / 'status_get'.
      #
      # The anonymous_user? guard matters: Secret#owner? compares objids, and
      # a guest-created secret (owner_id nil) fetched by an anonymous caller
      # (objid nil) would otherwise match nil == nil and misattribute the
      # access to "the creator".
      def record_access_telemetry(kind)
        return if secret.nil? || secret.receipt_identifier.to_s.empty?

        if !anonymous_user? && secret.owner?(cust)
          kind = kind.to_s == 'secret_get' ? 'previewed' : "creator_#{kind}"
        end

        receipt = secret.load_receipt
        receipt&.record_access_event(kind, context: request_network_context)
      rescue StandardError => ex
        OT.le "[access-telemetry] #{ex.class}: #{ex.message} (kind=#{kind})"
        nil
      end

      # Privacy-safe network context (#3640) for the fetch event, threaded down
      # to the model layer's org-trail fan-out (which has no request object of
      # its own). Reads the IP / User-Agent the auth strategy resolved into the
      # StrategyResult metadata -- in production these are ALREADY edge-masked
      # by Otto's IPPrivacyMiddleware -- and reduces them again, unconditionally,
      # to the stored representation: partial IP, partial UA, and a keyed
      # correlation hash. Raw IP / full UA are never stored; see
      # Onetime::Security::RequestContext and ADR-022 for the full stance.
      #
      # @return [Hash{String=>String}] string-keyed network attrs, forwarded via
      #   record_access_event(context:) -> record_org_audit_event(**event_attrs).
      #   Empty when no request context is available (e.g. in unit tests that
      #   supply no metadata), in which case the event records without them.
      def request_network_context
        metadata = strategy_result&.metadata || {}

        Onetime::Security::RequestContext.capture(
          ip: metadata[:ip],
          user_agent: metadata[:user_agent],
        )
      rescue StandardError => ex
        # Capture must never break the (best-effort) telemetry path; on any
        # failure fall back to recording the event with no network context.
        OT.le "[access-telemetry] network-context capture failed: #{ex.class}: #{ex.message}"
        {}
      end
    end
  end
end
