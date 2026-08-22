# apps/web/core/views/serializers/diagnostics_serializer.rb
#
# frozen_string_literal: true

require 'onetime/utils/diagnostics_ref'

module Core
  module Views
    # Serializes the pseudonymous user reference for the browser Sentry SDK.
    #
    # This is DIAGNOSTICS, not analytics: the reference exists so that an
    # operator reading an error event can tell one broken account from fifty.
    # Nothing here counts sessions, measures usage, or profiles behaviour.
    #
    # The frontend Sentry client needs a STABLE user reference so events group
    # per human instead of per session, but it must not learn who that human is.
    # This serializer emits only what Onetime::Utils::DiagnosticsRef derives: an
    # opaque keyed reference plus the label describing how far that reference
    # correlates.
    #
    #   diagnostics_ref: { user_ref: "<16 hex>", user_scope: "federated"|"deployment" }
    #
    # Never emitted, by construction: email, display name, custid, objid, extid,
    # IP address, or either keying secret. The pre-image never leaves the server.
    #
    # EXACTLY TWO KEYS. The frontend contract (diagnosticsRefSchema in
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
    # ACCEPTED DISCLOSURE: user_scope is configuration, not user data. The
    # label is a property of the KEY, so shipping it to every authenticated
    # browser tells that browser whether this install has FEDERATION_SECRET set
    # AND declares a data-residency scope ('federated'), or does not ('deployment').
    # That is deliberate and accepted, not an oversight:
    #
    #   * it is worth almost nothing to an attacker — it discloses no secret, no
    #     length, no derivation input, and both states are ordinary supported
    #     configurations, publicly documented in .env.reference;
    #   * it is only visible to a session that has already authenticated;
    #   * the frontend genuinely consumes it. It becomes a Sentry tag alongside
    #     the ref, and it is the ONLY thing that tells an operator reading an
    #     event how far the id is comparable — whether two matching refs from
    #     different instances are the same human or a coincidence of scope.
    #     Collapsing the label would make every ref look install-local and
    #     silently mislead on federated installs.
    #
    # ONE KEYING RESOLUTION. The ref and the label are taken from a single
    # DiagnosticsRef.user call, which resolves the residency scope once and
    # threads it through both. Do not decompose that into #user_ref plus
    # #scope: a config change between the two calls would pair a
    # federation-keyed ref with a 'deployment' label, telling the operator the
    # id correlates LESS far than it does.
    #
    # Re-examine this if the label ever gains a value that encodes something
    # about the ACCOUNT rather than about the key. It must not.
    #
    # NO ORGANIZATION REF HERE. A pseudonymous organization ref DOES exist —
    # Onetime::Utils::DiagnosticsRef.organization_ref, published on the colonel
    # organization-detail record — but it deliberately does not travel through
    # this block, and adding it here would be a regression twice over:
    #
    #   * MECHANICALLY, it is a third key in a strictObject.
    #     diagnosticsRefSchema rejects the object and the client discards
    #     user_ref and user_scope along with it, so the cost of widening this
    #     block is losing the user reference entirely — silently, since a failed
    #     parse is not an error.
    #
    #   * SEMANTICALLY, this block is PER-SESSION and the org ref is
    #     PER-RESOURCE. A session has one user but touches many organizations,
    #     so there is no single correct value to put here; whichever org
    #     happened to be current at render time would then be tagged onto every
    #     later event in the session, including events about other orgs.
    #
    # The org ref rides the response record it describes, and the frontend
    # attaches it as a tag for enrolled internal/admin schemas only.
    #
    # OMISSION, NOT NULLS. The `diagnostics_ref` key is absent from the payload
    # whenever there is nothing legitimate to say:
    #
    #   * anonymous sessions (no user to identify — an anonymous visitor must
    #     stay unidentified, matching SystemSerializer's withholding posture);
    #   * awaiting-MFA sessions (not yet authenticated);
    #   * deployments with no usable keying secret, which is the DEFAULT state
    #     in dev and test. "Usable" is narrower than "set": FEDERATION_SECRET is
    #     refused unless a data-residency scope is declared (DiagnosticsRef's
    #     fail-closed default against cross-region correlation), so an install
    #     with FEDERATION_SECRET, no residency and no ACCOUNT_ID_SECRET has
    #     nothing to key with and omits the block.
    #
    # Absence is unambiguous ("no reference"), whereas a null or empty-string
    # user_ref would be a value the client has to special-case. The frontend
    # reads the block as optional and skips Sentry.setUser when it is missing.
    #
    # The derivation raises no StandardError (see DiagnosticsRef), so an unconfigured install
    # renders exactly as it did before this serializer existed. That guarantee
    # matters here specifically: this serializer is registered on all three web
    # shells (apps/web/core/views.rb), so it runs on EVERY authenticated render,
    # including for accounts whose stored email is not valid UTF-8.
    module DiagnosticsSerializer
      # Serializes the pseudonymous user reference from view variables.
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

        # Exactly { 'user_ref' => ..., 'user_scope' => ... }, or nil when no
        # secret is configured / the derivation declined. Passed through
        # verbatim: the module owns the shape, and the client parses it strictly.
        diagnostics_ref = Onetime::Utils::DiagnosticsRef.user(cust.email)
        return omit(output) if diagnostics_ref.nil?

        output['diagnostics_ref'] = diagnostics_ref
        output
      end

      class << self
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

        # Drop the key so the payload carries no user reference at all.
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
