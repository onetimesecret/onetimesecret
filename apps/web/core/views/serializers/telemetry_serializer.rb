# apps/web/core/views/serializers/telemetry_serializer.rb
#
# frozen_string_literal: true

require 'onetime/utils/telemetry_ref'

module Core
  module Views
    # Serializes the pseudonymous telemetry identity for the browser SDK.
    #
    # The frontend Sentry client needs a STABLE actor identity so events group
    # per human instead of per session, but it must not learn who that human is.
    # This serializer emits only what Onetime::Utils::TelemetryRef derives: an
    # opaque keyed reference plus the label describing how far that reference
    # correlates.
    #
    #   telemetry: { actor_ref: "<16 hex>", actor_scope: "federated"|"deployment" }
    #
    # Never emitted, by construction: email, display name, custid, objid, extid,
    # IP address, or either keying secret. The pre-image never leaves the server.
    #
    # EXACTLY TWO KEYS. The frontend contract (telemetrySchema in
    # src/schemas/contracts/bootstrap.ts) is a Zod strictObject and is the one
    # schema actually parsed against live data — an extra key makes the parse
    # fail and the whole block is dropped rather than forwarded. That strictness
    # is the client-side enforcement of "nothing unexpected reaches Sentry", so
    # do not widen this block; anything else belongs on its own surface.
    #
    # ACCEPTED DISCLOSURE: actor_scope is configuration, not user data. The
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
    # TelemetryRef.actor call, which resolves the residency scope once and
    # threads it through both. Do not decompose that into #actor_ref plus
    # #scope: a config change between the two calls would pair a
    # federation-keyed ref with a 'deployment' label, telling the operator the
    # id correlates LESS far than it does.
    #
    # Re-examine this if the label ever gains a value that encodes something
    # about the ACCOUNT rather than about the key. It must not.
    #
    # NO ORGANIZATION REF HERE. A pseudonymous organization ref DOES exist —
    # Onetime::Utils::TelemetryRef.organization_ref, published on the colonel
    # organization-detail record — but it deliberately does not travel through
    # this block, and adding it here would be a regression twice over:
    #
    #   * MECHANICALLY, it is a third key in a strictObject. telemetrySchema
    #     rejects the object and the client discards actor_ref and actor_scope
    #     along with it, so the cost of widening this block is losing the actor
    #     identity entirely — silently, since a failed parse is not an error.
    #
    #   * SEMANTICALLY, this block is PER-SESSION and the org ref is
    #     PER-RESOURCE. A session has one actor but touches many organizations,
    #     so there is no single correct value to put here; whichever org
    #     happened to be current at render time would then be tagged onto every
    #     later event in the session, including events about other orgs.
    #
    # The org ref rides the response record it describes, and the frontend
    # attaches it as a tag for enrolled internal/admin schemas only.
    #
    # OMISSION, NOT NULLS. The `telemetry` key is absent from the payload
    # whenever there is nothing legitimate to say:
    #
    #   * anonymous sessions (no actor to identify — an anonymous visitor must
    #     stay unidentified, matching SystemSerializer's withholding posture);
    #   * awaiting-MFA sessions (not yet authenticated);
    #   * deployments with no usable keying secret, which is the DEFAULT state
    #     in dev and test. "Usable" is narrower than "set": FEDERATION_SECRET is
    #     refused unless a data-residency scope is declared (TelemetryRef's
    #     fail-closed default against cross-region correlation), so an install
    #     with FEDERATION_SECRET, no residency and no ACCOUNT_ID_SECRET has
    #     nothing to key with and omits the block.
    #
    # Absence is unambiguous ("no identity"), whereas a null or empty-string
    # actor_ref would be a value the client has to special-case. The frontend
    # reads the block as optional and skips Sentry.setUser when it is missing.
    #
    # The derivation cannot raise (see TelemetryRef), so an unconfigured install
    # renders exactly as it did before this serializer existed. That guarantee
    # matters here specifically: this serializer is registered on all three web
    # shells (apps/web/core/views.rb), so it runs on EVERY authenticated render,
    # including for accounts whose stored email is not valid UTF-8.
    module TelemetrySerializer
      # Serializes telemetry identity from view variables.
      #
      # @param view_vars [Hash] view variables (needs 'authenticated' and 'cust').
      # @return [Hash] { 'telemetry' => {...} }, or {} to omit the key entirely.
      def self.serialize(view_vars)
        output = output_template
        cust   = view_vars['cust']

        # Omit for anonymous. `authenticated` is false on the error-recovery
        # path too, which is the conservative answer there.
        return omit(output) unless view_vars['authenticated'] && cust

        # Exactly { 'actor_ref' => ..., 'actor_scope' => ... }, or nil when no
        # secret is configured / the derivation declined. Passed through
        # verbatim: the module owns the shape, and the client parses it strictly.
        telemetry = Onetime::Utils::TelemetryRef.actor(cust.email)
        return omit(output) if telemetry.nil?

        output['telemetry'] = telemetry
        output
      end

      class << self
        # Declares the output boundary for SerializerRegistry. A key absent
        # here is stripped from the payload, so `telemetry` must be declared
        # even though it is frequently omitted at runtime.
        #
        # @return [Hash] Template with all possible telemetry output fields
        def output_template
          {
            'telemetry' => nil,
          }
        end

        # Drop the key so the payload carries no telemetry block at all.
        #
        # @param output [Hash]
        # @return [Hash]
        def omit(output)
          output.delete('telemetry')
          output
        end
      end

      SerializerRegistry.register(self, ['AuthenticationSerializer'])
    end
  end
end
