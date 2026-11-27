# apps/api/v1/logic/secrets/access_telemetry.rb
#
# frozen_string_literal: true

module V1::Logic
  module Secrets
    # Records v1 secret link fetches on the receipt's access timeline
    # (Receipt::Features::AccessTimeline), which fans them out to the
    # organization's Secret Activity trail. The v1 sibling of
    # V2::Logic::Secrets::AccessTelemetry; keep the two logically parallel.
    #
    # Differences from V2: v1 has no secret status endpoint, so the only kind
    # recorded here is 'secret_get'; and v1 logic has no strategy_result, so
    # events carry no network context.
    #
    # Including classes must also include ActorAttribution.
    module AccessTelemetry
      private

      # Best-effort by design: telemetry must never break or delay the read
      # path, so every failure is logged and swallowed. Secrets without a
      # receipt (e.g. account-verification secrets) are skipped.
      #
      # The creator opening their own link is the 'previewed' event, as in
      # V2. The anonymous guard comes first: Secret#owner? compares objids,
      # so a guest-created secret fetched by an anonymous caller would match
      # nil == nil and be misattributed to the creator.
      def record_access_telemetry(kind)
        return if secret.nil? || secret.receipt_identifier.to_s.empty?

        if !(cust.nil? || cust.anonymous?) && secret.owner?(cust)
          kind = kind.to_s == 'secret_get' ? 'previewed' : "creator_#{kind}"
        end

        secret.load_receipt&.record_access_event(kind, context: lifecycle_actor_context(secret))
      rescue StandardError => ex
        OT.le "[access-telemetry] #{ex.class}: #{ex.message} (kind=#{kind})"
        nil
      end
    end
  end
end
