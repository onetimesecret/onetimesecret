# apps/api/v2/logic/secrets/access_telemetry.rb
#
# frozen_string_literal: true

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
      def record_access_telemetry(kind)
        return if secret.nil? || secret.receipt_identifier.to_s.empty?

        receipt = secret.load_receipt
        receipt&.record_access_event(kind)
      rescue StandardError => ex
        OT.le "[access-telemetry] #{ex.class}: #{ex.message} (kind=#{kind})"
        nil
      end
    end
  end
end
