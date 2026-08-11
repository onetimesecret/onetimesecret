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
    # record_org_secret_activity_event), which has no request context. So the discriminator
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
      #   anonymous           — unauthenticated caller
      #   unknown             — authenticated caller whose relationship to the
      #                         subject cannot be established (ADR-023)
      #
      # The optional 'actor_id' is the FULL objid of the acting customer (never
      # the email or custid). Unique traceability (NIST AU-3, PCI DSS 10.2.2)
      # requires binding each event to a uniquely resolvable individual, and a
      # customer objid grants no access -- unlike a secret identifier it is not
      # a capability token, so the shortid convention for receipt/secret ids
      # does not apply. Identity (email/display name) is resolved at read/
      # export time via an org-membership join and never enters the append-only
      # trail. Included only for authenticated actors, where a real objid
      # exists; anonymous events carry the discriminator alone.
      #
      # @param target_secret [Onetime::Secret, nil] the secret being consumed.
      # @return [Hash] string-keyed audit attrs, always carrying 'actor'.
      def lifecycle_actor_context(target_secret)
        return { 'actor' => 'anonymous' } if anonymous_user?

        # target_secret is the secret being consumed and is always in hand at
        # the reveal/burn call sites. Guard nil explicitly: without a secret we
        # cannot establish ownership, and `authenticated_other` would assert
        # "not the owner" -- a fact we cannot support. Record the explicit
        # `unknown` sentinel instead (ADR-023: never fabricate an actor),
        # keeping the authenticated principal's id. Surface it, but never
        # raise: attribution is best-effort observability and must not break
        # the consume path.
        actor               =
          if target_secret.nil?
            OT.le '[actor-attribution] nil target_secret for an authenticated ' \
                  'caller; ownership indeterminate, recording actor=unknown (ADR-023)'
            'unknown'
          elsif target_secret.owner?(cust)
            'creator'
          else
            'authenticated_other'
          end
        context             = { 'actor' => actor }
        # Only attach an id when we actually resolved one; never store a nil.
        objid               = actor_objid
        context['actor_id'] = objid unless objid.nil?
        context
      end

      # The FULL objid of the acting customer, recorded untruncated so the
      # trail binds the event to a uniquely resolvable individual (AU-3 /
      # PCI 10.2.2). Never the email or custid. Returns nil (dropped by the
      # caller) when no stable objid is available.
      def actor_objid
        objid = cust&.objid.to_s
        objid.empty? ? nil : objid
      end
    end
  end
end
