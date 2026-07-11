# apps/api/v2/logic/secrets/actor_attribution.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    # Computes the request-scoped actor attribution for secret lifecycle events
    # (revealed / burned) and threads it into the model cascade (#3639).
    #
    # The lifecycle emit happens deep inside the atomic consume cascade
    # (Secret#reveal!/#burned! -> Receipt#revealed!/#burned! ->
    # record_org_audit_event), which has no request context. So the discriminator
    # is computed HERE, where the request's customer (`cust`) is in scope, and
    # threaded down as an opaque `actor_context` hash.
    #
    # "Who revealed it" is the first question an auditor asks; before this the
    # revealed/burned events carried no actor at all — the highest-value gap in
    # the org audit pipeline.
    module ActorAttribution
      private

      # Build the actor-attribution audit context for a lifecycle transition.
      #
      # The ownership test mirrors the fetch-side telemetry
      # (AccessTelemetry#record_access_telemetry) EXACTLY, including the critical
      # anonymous guard: Secret#owner? compares objids, so a guest-created secret
      # (owner_id nil) inspected by an anonymous caller (objid nil) would match
      # `nil == nil` and misattribute the access to "the creator". Gating on
      # `!anonymous_user?` first means an anonymous caller never reaches owner?,
      # so an anonymous reveal/burn of a guest link is always 'anonymous' and
      # never 'creator'. See the same precedent in access_telemetry.rb.
      #
      #   creator             — authenticated caller who owns the secret
      #   authenticated_other — authenticated caller who does NOT own it
      #   anonymous           — unauthenticated caller (or unknown)
      #
      # The optional 'actor_id' is a SHORTID of the acting customer's internal
      # object identifier (never the email or full custid), matching the
      # shortids-only convention the trail already uses for receipt/secret ids
      # (Receipt#shortid). It is included only for authenticated actors, where a
      # real objid exists; anonymous events carry the discriminator alone.
      #
      # @param target_secret [Onetime::Secret, nil] the secret being consumed.
      # @return [Hash] string-keyed audit attrs, always carrying 'actor'.
      def lifecycle_actor_context(target_secret)
        return { 'actor' => 'anonymous' } if anonymous_user?

        # target_secret is the secret being consumed and is always in hand at
        # the reveal/burn call sites. Guard nil explicitly: without a secret we
        # cannot establish ownership, and letting it fall through owner? would
        # silently bucket the caller as `authenticated_other` -- a misleading
        # actor that also hides the programmer error. Surface it, but never
        # raise: attribution is best-effort observability and must not break
        # the consume path.
        if target_secret.nil?
          OT.le '[actor-attribution] nil target_secret for an authenticated ' \
                'caller; ownership indeterminate, recording actor=authenticated_other'
        end

        actor               = target_secret&.owner?(cust) ? 'creator' : 'authenticated_other'
        context             = { 'actor' => actor }
        # Only attach an id when we actually resolved one; never store a nil.
        shortid             = actor_shortid
        context['actor_id'] = shortid unless shortid.nil?
        context
      end

      # An 8-char shortid of the acting customer's object identifier, mirroring
      # Receipt#shortid (identifier.slice(0, 8)). Kept short and non-sensitive so
      # it can never leak an email or a capability token into the trail. Returns
      # nil (dropped by the caller) when no stable objid is available.
      def actor_shortid
        objid = cust&.objid.to_s
        objid.empty? ? nil : objid.slice(0, 8)
      end
    end
  end
end
