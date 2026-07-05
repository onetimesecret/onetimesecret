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
        receipt&.record_access_event(kind)
      rescue StandardError => ex
        OT.le "[access-telemetry] #{ex.class}: #{ex.message} (kind=#{kind})"
        nil
      end
    end
  end
end
