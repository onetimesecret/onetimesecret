# apps/api/v1/logic/secrets/actor_attribution.rb
#
# frozen_string_literal: true

module V1::Logic
  module Secrets
    # Actor attribution for v1 secret lifecycle events (#3639); the v1 sibling
    # of V2::Logic::Secrets::ActorAttribution, shared by ShowSecret (reveal)
    # and BurnSecret.
    #
    # Anonymous guard FIRST: Secret#owner? compares objids, so an anonymous
    # caller (nil objid) consuming a guest-created secret (nil owner) would
    # match nil == nil and be misattributed as the creator. V1::Logic::Base
    # does not include AuthorizationPolicies, so the canonical anonymous check
    # (cust.nil? || cust.anonymous?) is inlined here — same pattern as v1
    # ShowReceipt#receipt_view_actor_context.
    module ActorAttribution
      private

      # @param target_secret [Onetime::Secret] the secret being consumed.
      # @return [Hash] string-keyed audit attrs, always carrying 'actor'.
      def lifecycle_actor_context(target_secret)
        return { 'actor' => 'anonymous' } if cust.nil? || cust.anonymous?

        actor = target_secret.owner?(cust) ? 'creator' : 'authenticated_other'
        { 'actor' => actor, 'actor_id' => cust.objid }
      end
    end
  end
end
