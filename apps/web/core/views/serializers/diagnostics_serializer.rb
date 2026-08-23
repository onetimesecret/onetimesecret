# apps/web/core/views/serializers/diagnostics_serializer.rb
#
# frozen_string_literal: true

require 'onetime/utils/diagnostics_ref'

module Core
  module Views
    # Serializes the pseudonymous actor reference for the browser Sentry SDK.
    #
    # This is DIAGNOSTICS, not analytics: the reference exists so that an
    # operator reading an error event can tell one broken account from fifty.
    # Nothing here counts sessions, measures usage, or profiles behaviour.
    #
    # The frontend Sentry client needs a STABLE actor reference so events group
    # per account instead of per session, but it must not learn which account
    # that is. This serializer emits only what
    # Onetime::Utils::DiagnosticsRef derives: one opaque keyed reference.
    #
    #   diagnostics_ref: { actor_ref: "<16 hex>" }
    #
    # Never emitted, by construction: email, display name, custid, objid, extid,
    # IP address, or the keying secret. The pre-image — the customer extid — is
    # hashed here and never leaves the server through this block; the 16-hex
    # digest is the only thing the browser sees.
    #
    # EXACTLY ONE KEY. The frontend contract (diagnosticsRefSchema in
    # src/schemas/contracts/bootstrap.ts) is a Zod strictObject and is the one
    # schema actually parsed against live data — an extra key makes the parse
    # fail and the whole block is dropped rather than forwarded. That strictness
    # is the client-side enforcement of "nothing unexpected reaches Sentry", so
    # do not widen this block; anything else belongs on its own surface.
    #
    # Note the name: `diagnosticsRefSchema` is this block. It is NOT
    # `diagnosticsSchema`, which is the unrelated Sentry *configuration* block
    # on the same bootstrap payload.
    #
    # NO SCOPE LABEL. An earlier revision shipped an `actor_scope` label
    # describing which secret keyed the ref. There is now exactly one keying
    # (ACCOUNT_ID_SECRET) and refs are per-install by construction, so the label
    # had one constant value and was dropped from the wire contract. Do not
    # reintroduce a second key here to describe the keying; see
    # docs/specs/diagnostics/actor-ref-preimage-debate-decision.md.
    #
    # NO ORGANIZATION REF HERE. A pseudonymous organization ref DOES exist —
    # Onetime::Utils::DiagnosticsRef.organization_ref, published on the colonel
    # organization-detail record — but it deliberately does not travel through
    # this block, and adding it here would be a regression twice over:
    #
    #   * MECHANICALLY, it is a second key in a strictObject.
    #     diagnosticsRefSchema rejects the object and the client discards
    #     actor_ref along with it, so the cost of widening this block is losing
    #     the actor reference entirely — silently, since a failed parse is not
    #     an error.
    #
    #   * SEMANTICALLY, this block is PER-SESSION and the org ref is
    #     PER-RESOURCE. A session has one user but touches many organizations,
    #     so there is no single correct value to put here; whichever org
    #     happened to be current at render time would then be tagged onto every
    #     later event in the session, including events about other orgs.
    #
    # The org ref rides the response record it describes. The current frontend
    # does not parse or attach it to Sentry; organization correlation remains a
    # deferred feature until that end-to-end path is implemented.
    #
    # OMISSION, NOT NULLS. The `diagnostics_ref` key is absent from the payload
    # whenever there is nothing legitimate to say:
    #
    #   * anonymous sessions (no user to identify — an anonymous visitor must
    #     stay unidentified, matching SystemSerializer's withholding posture);
    #   * awaiting-MFA sessions (not yet authenticated);
    #   * deployments with no usable keying secret (ACCOUNT_ID_SECRET), which is
    #     the DEFAULT state in dev and test;
    #   * customers with no usable extid — the derivation declines rather than
    #     substituting some other identifier.
    #
    # Absence is unambiguous ("no reference"), whereas a null or empty-string
    # actor_ref would be a value the client has to special-case. The frontend
    # reads the block as optional and skips Sentry.setUser when it is missing.
    #
    # The derivation raises no StandardError (see DiagnosticsRef), so an unconfigured install
    # renders exactly as it did before this serializer existed. That guarantee
    # matters here specifically: this serializer is registered on all three web
    # shells (apps/web/core/views.rb), so it runs on EVERY authenticated render.
    module DiagnosticsSerializer
      # Serializes the pseudonymous actor reference from view variables.
      #
      # @param view_vars [Hash] view variables (needs 'authenticated' and 'cust').
      # @return [Hash] { 'diagnostics_ref' => {...} }, or {} to omit the key entirely.
      def self.serialize(view_vars)
        output = output_template
        cust   = view_vars['cust']

        # Omit for anonymous. `authenticated` is false on the error-recovery
        # path too, which is the conservative answer there.
        return omit(output) unless view_vars['authenticated'] && cust

        # Awaiting-MFA sessions are unauthenticated today, so the guard above
        # already omits them; this check keeps that invariant local instead of
        # inherited from AuthenticationSerializer's `authenticated` semantics.
        return omit(output) if view_vars['awaiting_mfa']

        # Exactly { 'actor_ref' => ... }, or nil when no secret is configured /
        # the derivation declined. Passed through verbatim: the module owns the
        # shape, and the client parses it strictly.
        diagnostics_ref = Onetime::Utils::DiagnosticsRef.actor(customer_extid(cust))
        return omit(output) if diagnostics_ref.nil?

        output['diagnostics_ref'] = diagnostics_ref
        output
      end

      class << self
        # The actor pre-image, read defensively.
        #
        # DiagnosticsRef swallows everything inside its own derivation, but the
        # READ happens out here: Familia's extid getter derives lazily and
        # raises ExternalIdentifierError when the objid is absent or its
        # provenance is unknown. On a serializer that runs on every
        # authenticated render, that raise would be a 500 page plus a
        # self-inflicted Sentry event, so an unreadable extid costs the ref and
        # nothing more.
        #
        # @param cust [Onetime::Customer]
        # @return [String, nil]
        def customer_extid(cust)
          cust.extid if cust.respond_to?(:extid)
        rescue StandardError
          nil
        end

        # Declares the output boundary for SerializerRegistry. A key absent
        # here is stripped from the payload, so `diagnostics_ref` must be declared
        # even though it is frequently omitted at runtime.
        #
        # @return [Hash] Template with all possible diagnostics output fields
        def output_template
          {
            'diagnostics_ref' => nil,
          }
        end

        # Drop the key so the payload carries no actor reference at all.
        #
        # @param output [Hash]
        # @return [Hash]
        def omit(output)
          output.delete('diagnostics_ref')
          output
        end
      end

      SerializerRegistry.register(self, ['AuthenticationSerializer'])
    end
  end
end
